cask "letthembuild" do
  version "1.1.43"

  on_arm do
    sha256 "ee65a39f7d23058144349cad1d3800aa8731491e542f7d3f2bb71b0b5c22459c"
    url "https://letthembuild.com/updates/LetThemBuild-#{version}-arm64-mac.zip"
  end
  on_intel do
    sha256 "c2a4b83b0301083c94eb47527434479d0f4d84fe8f266d9dbfa41f30a518157e"
    url "https://letthembuild.com/updates/LetThemBuild-#{version}-x64-mac.zip"
  end

  name "LetThemBuild"
  desc "AI group chat with hands: Claude, ChatGPT, Gemini and Grok build and review in your checkout"
  homepage "https://letthembuild.com"

  livecheck do
    url "https://letthembuild.com/updates/latest-mac.yml"
    regex(/version:\s*v?(\d+(?:\.\d+)+)/i)
  end

  auto_updates true
  depends_on macos: ">= :ventura"

  app "LetThemBuild.app"

  # The `ltb` command line. Builds up to 1.1.43 carry the script only inside
  # app.asar, where nothing outside the app can link it — so this release's
  # copy is written here at install time, verbatim from the same single source
  # the app installs from Settings. Newer builds ship it unpacked at
  # Contents/Resources/bin/letthembuild; when the cask moves past 1.1.43 this
  # preflight goes and a plain binary stanza takes over.
  preflight do
    File.write "#{staged_path}/ltb", <<~'CLI'
      #!/usr/bin/env bash
      #
      # The room, in the checkout you are standing in.
      #
      #   letthembuild review "add rate limiting and prove it holds"
      #   ltb review "check the auth flow for races" --rounds 3 --json
      #
      # `ltb` is the same command under a shorter name — this is one script, so the
      # two can never drift.
      #
      # It runs the installed LetThemBuild app with its window left out, so the
      # seats, keys and settings are the ones you already configured — including
      # CLI seats backed by subscriptions you already pay for. Exit code: 0 when
      # the reviewers agreed, 1 when they did not, 2 when the run itself failed.
      set -euo pipefail

      # Where the app lives depends on how it was installed: /Applications on a Mac
      # (drag-install or Homebrew), /opt/LetThemBuild from the deb and rpm packages.
      # LETTHEMBUILD_APP overrides both — point it at the .app bundle on macOS or the
      # install directory on Linux.
      if [ "$(uname)" = "Darwin" ]; then
        APP="${LETTHEMBUILD_APP:-/Applications/LetThemBuild.app}"
        BIN="$APP/Contents/MacOS/LetThemBuild"
      else
        APP="${LETTHEMBUILD_APP:-/opt/LetThemBuild}"
        BIN="$APP/letthembuild-desktop"
      fi
      SELF="$(basename "$0")"

      usage() {
        cat <<EOF
      $SELF — the LetThemBuild room, in this checkout.

        $SELF review "<what you want done>" [options]

      Options
        --rounds N        How many rounds of review. 0 means until they agree.
        --permission M    plan | manual | edits | auto | bypass. Default: auto.
        --cwd PATH        Which checkout. Defaults to where you are standing.
        --json            One JSON event per line, for scripts.
        --quiet           Only the verdict and the errors.
        --help            This.
        --version         The app's version.

      Exit codes
        0  the reviewers agreed
        1  they did not
        2  the run itself failed

      The seats, keys and models are the ones configured in the app, so a seat
      backed by a subscription costs nothing extra here. Nothing is sent anywhere
      the app would not send it.

      Examples
        $SELF review "add rate limiting to the upload endpoint and prove it holds"
        $SELF review "check the auth flow for races" --rounds 3
        $SELF review "audit this for N+1 queries" --permission plan --json
      EOF
      }

      missing_app() {
        echo "LetThemBuild is not installed at $APP." >&2
        echo "Install it from https://letthembuild.com/download, or set LETTHEMBUILD_APP" >&2
        echo "to the app's path if it lives somewhere else." >&2
        exit 2
      }

      # Help, version and a bare invocation are answered HERE, without starting the
      # app. They used to fall through to it, and since the app does not recognise
      # them it did the only thing it knew: opened a second window and sat there. A
      # command-line tool that opens a window when you ask it for help is broken.
      case "${1:-}" in
        ""|-h|--help|help)
          usage
          [ -z "${1:-}" ] && exit 2 || exit 0
          ;;
        -V|--version|version)
          # Out of the bundle's own Info.plist, not by running the app. Launching a
          # GUI binary to ask its version means waiting for it to start, and an app
          # older than this script would not recognise the flag at all — it would
          # open a window and sit there, which is exactly the bug this case exists
          # to prevent.
          [ -d "$APP" ] || missing_app
          if [ "$(uname)" = "Darwin" ]; then
            /usr/bin/defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null \
              || /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null \
              || { echo "Could not read the version from $APP." >&2; exit 2; }
          else
            # On Linux the package manager that installed it is the authority.
            dpkg-query -W -f='${Version}\n' letthembuild-desktop 2>/dev/null \
              || rpm -q --qf '%{VERSION}\n' letthembuild-desktop 2>/dev/null \
              || { echo "Could not read the installed version — is LetThemBuild installed via deb or rpm?" >&2; exit 2; }
          fi
          exit 0
          ;;
        review) ;;                       # the only real subcommand, for now
        -*)
          echo "$SELF: unknown option $1" >&2
          echo "Try: $SELF --help" >&2
          exit 2
          ;;
        *)
          echo "$SELF: unknown command \"$1\" — did you mean \"$SELF review\"?" >&2
          echo "Try: $SELF --help" >&2
          exit 2
          ;;
      esac

      [ -x "$BIN" ] || missing_app

      # --cwd defaults to where you are, which is the whole point of a local CLI.
      has_cwd=false
      for arg in "$@"; do [ "$arg" = "--cwd" ] && has_cwd=true; done

      if [ "$has_cwd" = true ]; then
        exec "$BIN" "$@"
      else
        exec "$BIN" "$@" --cwd "$PWD"
      fi
    CLI
    FileUtils.chmod 0755, "#{staged_path}/ltb"
  end
  binary "#{staged_path}/ltb", target: "ltb"
  binary "#{staged_path}/ltb", target: "letthembuild"

  zap trash: [
    "~/Library/Application Support/LetThemChat",
    "~/Library/Logs/letthembuild-vscode.log",
    "~/Library/Logs/letthembuild-cursor.log",
  ]

  caveats <<~EOS
    The room's seats, keys and settings are configured in the app itself —
    open LetThemBuild once before using `ltb` from a terminal.
  EOS
end
