#!/usr/bin/perl -w
# TCP<->WebSocket connection proxy
# Copyright 2002-2014 Bernhard M. Wiedemann <httpdbmw@lsmod.de>
# 
# this is is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License
#
# zypper in perl-Protocol-WebSocket

use strict;
our (%options,%denv,%clientdata,
$cgi,$sel,$path,@shorterror,@longerror);

%options=qw(
port		8080
to       ws://localhost:9001/
logfile		/var/log/httpd/connectionproxy
uid		48
debug		1
);

use IO::Socket;
use IO::Select;
use Getopt::Long;
use FileHandle;
use Protocol::WebSocket::Handshake::Client;

($path=$0)=~s+[^/]*$++;$path="./" if($path eq "");
#require $path.'blib.pl';

sub defaults1 ($$) {$_[0]=$_[1] unless(defined($_[0]))}
sub defaults2 ($$) {$_[0]=$_[1] unless(defined($_[0]) and $_[0] ne "")}
sub diag ($;$) {my($m,$l)=@_;print STDERR "DIAGNOSTIC: $m\n" if($options{debug} || $l);}
sub accesslog($) {
	my ($client)=@_;
}


sub parseoptions()
{
 my @options=qw(port=i uid=i debug|d! to=s logfile:s
help|h|?
);
 my($paramfile)=($path."bmwrc");
 local @ARGV=@ARGV;
 use Config;
 if(@ARGV and substr($ARGV[0],0,1) ne "-") {$paramfile=shift @ARGV}
 if(open(S, "< $paramfile")) {
   local(@ARGV)=<S>;close(S);
   foreach(@ARGV) {if(s/^#.*//s){next} s/\015?\012|\n//; s/^/--/; s/ /=/;}
   if(!GetOptions(\%options, @options) || (@ARGV && $ARGV[0] ne "")) {die "invalid option in $paramfile. @ARGV\n"}
 }
 if(!GetOptions(\%options, @options) || (@ARGV && $ARGV[0] ne "")) {die "invalid option on commandline. @ARGV\n"}
 if($options{help}) {foreach(@options){m/([a-z]*)(.*)/;print "$1=$options{$1} ($2)\n"}; exit(0);}
 while(my @a=each(%options)) {if($a[1] eq "-"){$options{$a[0]}=""}}
}

sub openlog() {
   return 0;
	if($options{logfile}) {open(LOG, ">> $options{logfile}") or die "error opening $options{logfile}: $!";}
	select((select(LOG), $| = 1)[0]); #imediately flush log
}

sub closecon($) {
  my ($client)=@_;
  return unless $client;
  diag($client->peerhost.":".$client->peerport." connection closed");
  $sel->remove($clientdata{$client}->{fd});
  close($clientdata{$client}->{fd});
  delete($clientdata{$client});
  $sel->remove($client);
  close($client);
  return 0;
}


# main

parseoptions();

my @header=("Sec-WebSocket-Protocol: binary");
if($options{to}=~m/token=([^;&]*)/) {
  push(@header, "Cookie: token=$1");
}
$options{to}=~s{http(s?)(://[^/]+)/vnc.*}{ws$1$2/websockify};

our $haveinet6;
eval{require IO::Socket::INET6;} and ($haveinet6=1);
my $class="IO::Socket::INET".($haveinet6?"6":"");
my $new_client=$class->new(Proto=>"tcp", LocalPort=> $options{port}, Listen=>2, Reuse=>1) 
  or die "Can not open listen port $options{port}\n";

#use Net::Server::Daemonize qw(daemonize);
if(!$options{debug} && $>==0 ) {
#   daemonize($options{uid}, "nobody", "/var/run/bmwtinyhttpd.pid");
}
if($>==0 && $options{uid}) {
  umask(0002);
  $>=$)=$options{uid};
  $options{uid} == $> or 
       die "unable to setuid($options{uid})";
}
openlog();
diag("listening on port $options{port}");


$/="\012";
{
  my $s=$Config{sig_name};
  if($s=~m/\bHUP\b/) {$SIG{HUP} = sub{parseoptions();openlog()};}
  if($s=~m/\bPIPE\b/) {$SIG{PIPE} = 'IGNORE';}
  if($s=~m/\bCHLD\b/) {$SIG{CHLD} = sub{wait()} }
}

$sel = IO::Select->new($new_client);

MAINLOOP:
while (1) {
  my @ready = $sel->can_read(1);
  my @writeable = $sel->can_write(0);
  CLIENTLOOP:
  foreach my $client (@ready) {
   if($client == $new_client) {
     my $add = $client->accept;
     my $client=$add;

     my $tohostport=$options{to};
     my $classclient = $class;
     if($tohostport=~s{^ws://([^/]*).*}{$1}) {
     } elsif($tohostport=~s{^wss://([^/]*).*}{$1}) {
        require IO::Socket::SSL;
        $classclient = "IO::Socket::SSL";
     }
     my $sock = $classclient->new(PeerAddr => $tohostport, Proto=>"tcp", Timeout=>10);
     if(!$sock){
        closecon($client);
        next;
     }
     my $h = Protocol::WebSocket::Handshake::Client->new(url => $options{to});
     my $upgrade=$h->to_string;
     if(@header) {
        my $h=join("\015\012", @header);
        $upgrade=~s/^Upgrade: /$h\015\012$&/m;
     }
     diag($upgrade);
     if(!syswrite($sock, $upgrade)) {
        closecon($client);
        next;
     }
     
     $sel->add($add);
     diag($add->peerhost.":".$add->peerport." connected");
     my %cenv=%denv;
      $cenv{SERVER_ADDR}=$client->sockhost;
      $cenv{SERVER_PORT}=$client->sockport;
      $cenv{REMOTE_ADDR}=$client->peerhost;
      $cenv{REMOTE_PORT}=$client->peerport;
     ${$clientdata{$client}}{time}=time();
     ${$clientdata{$client}}{ENV}=\%cenv;
     $clientdata{$client}->{fd}=$sock;
     $clientdata{$client}->{h}=$h;
     $clientdata{$client}->{state}="connected";
     $clientdata{$sock}->{state}="handshake";
     $clientdata{$sock}->{fd}=$client;
     $clientdata{$sock}->{ws}=1;
     $clientdata{$sock}->{frame}=Protocol::WebSocket::Frame->new;
     $clientdata{$sock}->{h}=$h;
     $sel->add($sock);
   }
   elsif($clientdata{$client}) {
     $_=undef;
     my $nr=sysread $client, $_, 65535;
     if((!defined $_) || $nr<=0) {
         closecon($client);diag("client closed");next
     }
     my $h=$clientdata{$client}->{h};
     if($clientdata{$client}->{state} eq "handshake") {
       #diag("WS reply: '$_'");
       $h->parse($_);
       if($h->error) {
         closecon($client);diag("WS handshake error");next
       }
       if($h->is_done) {
         diag("WS connected");
         $clientdata{$client}->{state}="connected";
         next unless $_;
       }
     }
     my $frame;
     if($clientdata{$client}->{state} eq "connected") {
       if($clientdata{$client}->{ws}) {
         # ws-decapsulate
         $frame = $clientdata{$client}->{frame};
         $frame->append($_);
         $_="";
         while(defined(my $body = $frame->next_bytes)) {
           #diag("WS recv '$body'");
           if($frame->is_text || $frame->is_binary) {
             $_.=$body;
           }
           elsif($frame->is_close) {
             closecon($client);diag("WS close");next
           }
         }
       } else {
         # ws-encapsulate
         $frame=Protocol::WebSocket::Frame->new(buffer=>$_, masked=>1, type=>'binary');
         $_=$frame->to_bytes;
       }
       syswrite($clientdata{$client}->{fd}, $_) if $clientdata{$client};
     }
   }
  }
}
