# A live feed from the USB webcam, served over plain HTTP. The camera is a USB
# device that moves between machines, so nothing here is tied to one host:
# `fleet.services.Camera.host` below is the only thing that decides where it
# runs, and the encoder is chosen by probing whatever GPU that machine has.
{
  config,
  lib,
  ...
}: let
  port = 1984;

  service = config.fleet.services.Camera;

  # The edge proxy deliberately skips services it hosts itself, and a host-proxy
  # exists only on hosts that declare a `proxyPort`. A service living on the
  # edge therefore falls through both and has to publish its own virtual host --
  # the same thing the directory page and Authelia do.
  onEdge = service.host == config.fleet.edgeHost;

  # The AUKEY PC-LM1E registers two /dev/video* nodes and only the first of them
  # can capture, so a udev rule pins the capture node to a stable name rather
  # than trusting the enumeration order that gave it /dev/video0 this boot.
  usb = {
    vendor = "0458";
    product = "6006";
  };
  deviceName = "camera-webcam";
  device = "/dev/${deviceName}";

  streamName = "webcam";

  # MJPEG is the only format the camera offers above 7.5 fps, so that is what we
  # capture -- but we re-encode to H.264 instead of passing the JPEGs through.
  # Passthrough hands go2rtc a bare concatenated-JPEG pipe that it has to
  # re-split by scanning for markers, which intermittently yields truncated
  # frames ("image corrupt or truncated" in the browser), and it costs 33 Mbit/s
  # because this sensor's JPEGs run ~225 KB each. H.264 is properly framed over
  # RTSP and ~3.6 Mbit/s. Which encoder produces it is decided below, per host.
  stream = "ffmpeg:device?video=${device}&input_format=mjpeg&video_size=1280x720&framerate=30#video=h264";
in {
  fleet.services.Camera = {
    host = "krypton";
    title = "Camera";
    description = "Live webcam feed";
    subdomain = "camera";
    localProxy.port = port;
  };

  flake.modules.nixos.Camera = {
    config,
    pkgs,
    ...
  }: let
    # Encode on the GPU wherever the host has a graphics driver to do it with.
    #
    # go2rtc's own `#hardware` flag is not usable here. It always prepends
    # `-hwaccel vaapi -hwaccel_output_format vaapi`, which decodes the camera's
    # JPEGs on the GPU into 4:2:2 surfaces that h264_vaapi then refuses with
    # "No usable encoding profile found". Overriding the H.264 template instead
    # keeps the JPEG decode in software (it is cheap) and uploads plain NV12,
    # which the encoder does accept.
    #
    # `-low_power 1` selects the VDENC entrypoint -- the only H.264 encode path
    # Gemini Lake exposes -- and the explicit `-init_hw_device`/`-filter_hw_device`
    # pair is what gives `hwupload` a device to upload to.
    vaapi = {
      global = "-hide_banner -init_hw_device vaapi=va:/dev/dri/renderD128 -filter_hw_device va";
      h264 = "-vf format=nv12,hwupload -c:v h264_vaapi -low_power 1 -g 50 -bf 0 -profile:v high -level:v 4.1 -sei:v 0";
    };
    useVaapi = config.hardware.graphics.enable;

    # go2rtc's own player, but landing straight on the camera and pinned to MSE.
    # Its stock page tries WebRTC first -- which cannot work with the WebRTC
    # listener off -- and then falls back to pushing each frame into a <video>
    # element's `poster` as a base64 data URL, which is the black-then-frame
    # flicker. MSE plays the H.264 track as an ordinary buffered video.
    viewer = pkgs.writeText "index.html" ''
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Camera</title>
          <style>
            html, body { height: 100%; margin: 0; background: #000; }
            video-stream { display: block; width: 100%; height: 100%; }
          </style>
        </head>
        <body>
          <script type="module" src="./video-stream.js"></script>
          <script type="module">
            const video = document.createElement('video-stream');
            video.mode = 'mse';
            video.background = true;
            video.src = new URL('api/ws?src=${streamName}', location.href);
            document.body.appendChild(video);
          </script>
        </body>
      </html>
    '';

    # Serving our own static root replaces go2rtc's bundled UI wholesale, so
    # keep its pages -- the player component above is one of them -- and move
    # its stream list aside rather than losing it.
    www = pkgs.runCommand "go2rtc-www" {} ''
      cp -r ${pkgs.go2rtc.src}/www $out
      chmod -R u+w $out
      mv $out/index.html $out/streams.html
      cp ${viewer} $out/index.html
    '';
  in {
    # Only reached when the camera lives on the edge; everywhere else the
    # host-proxy routes to it from `localProxy.port` above.
    services.caddy.virtualHosts = lib.optionalAttrs onEdge {
      ${service.fqdn}.extraConfig = "reverse_proxy 127.0.0.1:${toString port}";
    };

    # go2rtc runs as a DynamicUser; `video` comes from the upstream module for
    # the capture device, and `render` is what lets it reach /dev/dri for the
    # hardware encoder.
    systemd.services.go2rtc.serviceConfig.SupplementaryGroups = ["render"];

    services.udev.extraRules = ''
      SUBSYSTEM=="video4linux", ATTRS{idVendor}=="${usb.vendor}", ATTRS{idProduct}=="${usb.product}", ENV{ID_V4L_CAPABILITIES}=="*:capture:*", SYMLINK+="${deviceName}"
    '';

    services.go2rtc = {
      enable = true;
      settings = {
        # The host proxy is go2rtc's only entry point, so nothing here binds a
        # public address. RTSP still needs a local one: a transcoding `ffmpeg:`
        # source hands its output back through go2rtc's own RTSP server, and
        # disabling the module outright fails the stream with "rtsp module
        # disabled". MSE rides the HTTP API's websocket, so WebRTC -- the only
        # part that would need a port reachable from the client -- stays off.
        api.listen = "127.0.0.1:${toString port}";
        api.static_dir = "${www}";
        rtsp.listen = "127.0.0.1:8554";
        webrtc.listen = "";

        # Left alone on a host without a graphics driver, where go2rtc's stock
        # libx264 template is the right answer.
        ffmpeg = lib.optionalAttrs useVaapi vaapi;

        streams.${streamName} = stream;
      };
    };
  };
}
