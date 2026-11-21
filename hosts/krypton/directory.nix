{
  config,
  lib,
  pkgs,
  ...
}: let
  dns = config.identity.homelab.dns;
  renderLinks = lib.concatMapStringsSep "\n" (service: ''
    <li><a href="${lib.escapeXML service.url}"><strong>${lib.escapeXML service.title}</strong><span>${lib.escapeXML service.description}</span></a></li>
  '');
  publicServices =
    config.network.hosts
    |> lib.mapAttrsToList (_: host:
      host.publicWebServices
      |> lib.filterAttrs (_: service: service.showInDirectory)
      |> lib.mapAttrsToList (_: service: let
        serviceHost = "${lib.optionalString (service.subdomain != null) "${service.subdomain}."}${dns}";
      in
        service
        // {
          url = "https://${serviceHost}${service.path}";
        }))
    |> lib.concatLists;
  directoryLinks = renderLinks publicServices;
  directoryPage = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Homelab services</title>
        <style>
          :root {
            color-scheme: light dark;
            font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            --page: #fafafa;
            --card: #ffffff;
            --card-hover: #f6f5f4;
            --border: #deddda;
            --text: #2e3436;
            --muted: #5e5c64;
            --accent: #3584e4;
            --shadow: 0 2px 6px rgb(0 0 0 / 12%);
          }
          * { box-sizing: border-box; }
          body {
            min-height: 100vh;
            max-width: 56rem;
            margin: 0 auto;
            padding: clamp(3rem, 10vh, 6rem) 1.5rem;
            background: var(--page);
            color: var(--text);
          }
          h1 { margin: 0; font-size: 2rem; line-height: 1.2; letter-spacing: -.02em; }
          h2 { margin: 0; font-size: 1.4rem; }
          hr { margin: 2.5rem 0; border: 0; border-top: 1px solid var(--border); }
          p { margin: .5rem 0 0; color: var(--muted); }
          ul {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr));
            gap: 1rem;
            padding: 0;
            margin: 2rem 0 0;
            list-style: none;
          }
          a {
            display: block;
            min-height: 7rem;
            padding: 1.25rem;
            border: 1px solid var(--border);
            border-radius: 12px;
            background: var(--card);
            box-shadow: var(--shadow);
            color: var(--text);
            text-decoration: none;
            transition: background-color 120ms ease, border-color 120ms ease, transform 120ms ease;
          }
          a:hover { border-color: var(--accent); background: var(--card-hover); transform: translateY(-1px); }
          a:active { transform: translateY(0); }
          a:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; }
          strong, span { display: block; }
          strong { font-size: 1.05rem; font-weight: 700; }
          span { margin-top: .45rem; font-size: .9rem; line-height: 1.4; color: var(--muted); }
          @media (prefers-color-scheme: dark) {
            :root {
              --page: #303030;
              --card: #3b3b3b;
              --card-hover: #424242;
              --border: #555555;
              --text: #ffffff;
              --muted: #deddda;
              --accent: #62a0ea;
              --shadow: 0 2px 6px rgb(0 0 0 / 35%);
            }
          }
          @media (prefers-reduced-motion: reduce) { a { transition: none; } }
        </style>
      </head>
      <body>
        <h1>The Inner Circle</h1>
        <ul>
          ${directoryLinks}
        </ul>

      </body>
    </html>
  '';
in {
  services.caddy.virtualHosts.${dns}.extraConfig = lib.mkBefore ''
    handle / {
      forward_auth 127.0.0.1:9091 {
        uri /api/authz/forward-auth
        header_up X-Forwarded-Proto https
        copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
      }
      root * ${directoryPage}
      file_server
    }
  '';
}
