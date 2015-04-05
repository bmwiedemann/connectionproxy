PREFIX=/usr/local/
all:
	echo nothing to compile

install:
	for f in novncviewer wsconnectionproxy.pl ; do install -D -m 755 $$f ${DESTDIR}${PREFIX}/bin/$$f ; done

test:
	./novncviewer

installdeps:
	OneClickInstallCLI "http://multiymp.zq1.de/perl-Net-OpenStack-Compute?base=http://download.opensuse.org/repositories/devel:/languages:/perl/"
	zypper -n install perl-Protocol-WebSocket

