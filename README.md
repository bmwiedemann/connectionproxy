## novncviewer

allows to connect to OpenStack cloud instance VMs using the VNC client of your choice.

    . openrc.sh
    #export VNCVIEWER=gvncviewer
    novncviewer 16505a6c-0aae-44b0-a720-17eb80f821ed &

Internally this uses
wsconnectionproxy.pl that proxies and translates plain TCP connections
into WebSocket connections


examples:

    perl wsconnectionproxy.pl --to ws://example.com:1234/demo
    perl wsconnectionproxy.pl --to http://cloud.example.com:6080/vnc_auto.html?token=73a3e035-cc28-49b4-9013-a9692671788e
