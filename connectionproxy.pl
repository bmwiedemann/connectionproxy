#!/usr/bin/perl -w
# TCP connection proxy
# Copyright 2002 Bernhard M. Wiedemann <httpdbmw@lsmod.de>
# 
# this is is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2

use strict;
our (%options,%denv,%clientdata,
$cgi,$sel,$path,@shorterror,@longerror);

%options=qw(
port		993
to       mail.zq1.de:993
logfile		/var/log/httpd/connectionproxy
uid		48
debug		0
);

use IO::Socket;
use IO::Select;
use Getopt::Long;
use FileHandle;
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
our $haveinet6;
eval{require IO::Socket::INET6;} and ($haveinet6=1);
my $class="IO::Socket::INET".($haveinet6?"6":"");
my $new_client=$class->new(Proto=>"tcp", LocalPort=> $options{port}, Listen=>2, Reuse=>1) 
  or die "Can not open listen port $options{port}\n";

#use Net::Server::Daemonize qw(daemonize);
#if(!$options{debug} && $>==0 ) {
#   daemonize($options{uid}, "nobody", "/var/run/bmwtinyhttpd.pid");
#}
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

     my $sock= new IO::Socket::INET6(PeerAddr => $options{to}, Proto=>"tcp", Timeout=>10);
     if(!$sock){
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
     $clientdata{$sock}->{fd}=$client;
     $sel->add($sock);
   }
   elsif($clientdata{$client}) {
     $_=undef;
     my $nr=sysread $client, $_, 65000;
     if((!defined $_) || $nr==0) {
         closecon($client);diag("client closed");next
     }
     syswrite($clientdata{$client}->{fd}, $_);
	}
  }
}
