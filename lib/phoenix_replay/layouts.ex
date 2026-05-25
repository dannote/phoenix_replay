defmodule PhoenixReplay.Layouts do
  @moduledoc false
  use Phoenix.Component

  def frame(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <link rel="stylesheet" href="/assets/css/app.css" />
        <style>
          body { margin: 0; pointer-events: none; user-select: none; }
        </style>
        <script defer type="text/javascript" src="/assets/js/app.js">
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>{assigns[:page_title] || "PhoenixReplay"}</title>
        <link rel="stylesheet" href="/assets/css/app.css" />

        <script defer type="text/javascript" src="/assets/js/app.js">
        </script>
      </head>
      <body class="m-0 font-sans bg-neutral-100 text-neutral-900 antialiased">
        {@inner_content}
      </body>
    </html>
    """
  end
end
