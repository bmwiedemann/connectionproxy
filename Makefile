test:
	./novncviewer

installdeps:
	OneClickInstallCLI "http://multiymp.zq1.de/perl-Net-OpenStack-Compute?base=http://download.opensuse.org/repositories/devel:/languages:/perl/"
	zypper -n install perl-Protocol-WebSocket

