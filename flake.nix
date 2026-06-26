{
  description = "Render Markdown as Kitty graphics protocol in the terminal";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems =
        f:
        builtins.listToAttrs (
          map (system: {
            name = system;
            value = f system;
          }) systems
        );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          fontConf = pkgs.makeFontsConf {
            fontDirectories = [
              pkgs.noto-fonts
              pkgs.noto-fonts-cjk-sans
              pkgs.noto-fonts-color-emoji
              pkgs.dejavu_fonts
            ];
          };
        in
        {
          mdkitty = pkgs.writeShellApplication {
            name = "mdkitty";

            runtimeInputs = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gnugrep
              pkgs.imagemagick
              pkgs.kitty
              pkgs.less
              pkgs.pandoc
              pkgs."poppler-utils"
              pkgs.python3Packages.weasyprint
            ];

            text = ''
              set -euo pipefail

              export FONTCONFIG_FILE="${fontConf}"

              usage() {
                cat <<'EOF'
Usage: mdkitty [options] FILE.md
       mdkitty [options] -

Render Markdown into one continuous image and display it with Kitty graphics.

Options:
  --pager          open the Kitty graphics stream in less -r, default
  --no-pager       render directly into terminal scrollback
  --pdf            open the rendered PDF with open
  --stdout         write Kitty graphics protocol to stdout
  --out-dir DIR    copy the rendered HTML, PDF, and PNG to DIR
  --cache-dir DIR  cache directory, default: $XDG_CACHE_HOME/mdkitty
  --no-cache       render without reading or writing the cache
  --width PX       output image width, default: 1100
  --landscape      format the document on landscape Letter pages
  --title TITLE    HTML page title used by Pandoc
  -h, --help       show this help

Examples:
  nix run . -- README.md
  nix run . -- --no-pager notes.md
  nix run . -- --out-dir render notes.md
  cat notes.md | nix run . -- -
EOF
              }

              mode=pager
              out_dir=
              cache_dir=
              cache=1
              width=1100
              page_size="8.5in 11in"
              body_max_width=920
              title=
              input=

              while [ "$#" -gt 0 ]; do
                case "$1" in
                  --pager)
                    mode=pager
                    shift
                    ;;
                  --no-pager|--view)
                    mode=view
                    shift
                    ;;
                  --pdf)
                    mode=pdf
                    shift
                    ;;
                  --stdout)
                    mode=stdout
                    shift
                    ;;
                  --out-dir)
                    if [ "$#" -lt 2 ]; then
                      echo "mdkitty: --out-dir requires a directory" >&2
                      exit 2
                    fi
                    out_dir=$2
                    shift 2
                    ;;
                  --cache-dir)
                    if [ "$#" -lt 2 ]; then
                      echo "mdkitty: --cache-dir requires a directory" >&2
                      exit 2
                    fi
                    cache_dir=$2
                    shift 2
                    ;;
                  --no-cache)
                    cache=0
                    shift
                    ;;
                  --width)
                    if [ "$#" -lt 2 ]; then
                      echo "mdkitty: --width requires a value" >&2
                      exit 2
                    fi
                    width=$2
                    shift 2
                    ;;
                  --landscape)
                    page_size="11in 8.5in"
                    body_max_width=1260
                    shift
                    ;;
                  --title)
                    if [ "$#" -lt 2 ]; then
                      echo "mdkitty: --title requires a value" >&2
                      exit 2
                    fi
                    title=$2
                    shift 2
                    ;;
                  -h|--help)
                    usage
                    exit 0
                    ;;
                  --)
                    shift
                    break
                    ;;
                  -)
                    if [ -n "$input" ]; then
                      echo "mdkitty: only one input file is supported" >&2
                      exit 2
                    fi
                    input=$1
                    shift
                    ;;
                  -*)
                    echo "mdkitty: unknown option: $1" >&2
                    usage >&2
                    exit 2
                    ;;
                  *)
                    if [ -n "$input" ]; then
                      echo "mdkitty: only one input file is supported" >&2
                      exit 2
                    fi
                    input=$1
                    shift
                    ;;
                esac
              done

              if [ -z "$input" ] && [ "$#" -gt 0 ]; then
                input=$1
                shift
              fi

              if [ -z "$input" ] || [ "$#" -gt 0 ]; then
                usage >&2
                exit 2
              fi

              if ! [[ "$width" =~ ^[0-9]+$ ]] || [ "$width" -lt 480 ]; then
                echo "mdkitty: --width must be an integer greater than or equal to 480" >&2
                exit 2
              fi

              tmp=$(mktemp -d)
              cleanup() {
                rm -rf "$tmp"
              }
              trap cleanup EXIT

              css=$tmp/markdown.css
              html=$tmp/markdown.html
              pdf=$tmp/markdown.pdf
              image=$tmp/markdown.png

cat > "$css" <<EOF
@page {
  size: $page_size;
  margin: 0;
}

:root {
  color: #24292f;
  background: #eef1f4;
}

html {
  background: #eef1f4;
  font-family: "Noto Sans", "DejaVu Sans", sans-serif;
  font-size: 16px;
  line-height: 1.5;
  min-height: 100%;
}

body {
  background: #ffffff;
  box-sizing: border-box;
  color: #24292f;
  margin: 0 auto;
  max-width: ''${body_max_width}px;
  min-height: 100vh;
  padding: 48px 56px 64px;
  width: 100%;
}

h1,
h2,
h3,
h4 {
  color: #111827;
  font-weight: 700;
  line-height: 1.18;
  margin: 1.4em 0 0.52em;
  page-break-after: avoid;
}

h1 {
  font-size: 34px;
  padding-bottom: 14px;
  border-bottom: 1px solid #d8dee4;
  margin-top: 0;
}

h2 {
  font-size: 25px;
  padding-bottom: 8px;
  border-bottom: 1px solid #e5e7eb;
}

h3 {
  font-size: 20px;
}

h4 {
  font-size: 17px;
}

p,
ul,
ol,
blockquote,
pre,
table {
  margin-top: 0;
  margin-bottom: 0.85em;
}

a {
  color: #0969da;
  text-decoration: none;
}

code,
pre {
  font-family: "Noto Sans Mono", "DejaVu Sans Mono", monospace;
  font-size: 0.92em;
}

code {
  background: #f6f8fa;
  border-radius: 4px;
  padding: 0.12em 0.32em;
}

pre {
  background: #f6f8fa;
  border: 1px solid #d8dee4;
  border-radius: 6px;
  line-height: 1.42;
  overflow-wrap: break-word;
  padding: 0.72em 0.85em;
  white-space: pre-wrap;
}

pre code {
  background: transparent;
  border-radius: 0;
  padding: 0;
}

blockquote {
  border-left: 4px solid #d0d7de;
  color: #57606a;
  padding: 0.1em 0 0.1em 0.9em;
}

table {
  border-collapse: collapse;
  display: table;
  font-size: 0.94em;
  width: 100%;
}

th,
td {
  border: 1px solid #d8dee4;
  padding: 0.42em 0.56em;
  vertical-align: top;
}

th {
  background: #f6f8fa;
  color: #111827;
  font-weight: 700;
}

img,
svg {
  display: block;
  height: auto;
  margin: 1em auto;
  max-width: 100%;
}

hr {
  border: 0;
  border-top: 1px solid #d8dee4;
  margin: 1.35em 0;
}

.sourceCode {
  background: #f6f8fa;
}
EOF

              if [ "$input" = "-" ]; then
                md=$tmp/stdin.md
                cat > "$md"
                resource_path=$(pwd)
                if [ -z "$title" ]; then
                  title=stdin
                fi
              else
                if [ ! -f "$input" ]; then
                  echo "mdkitty: input file not found: $input" >&2
                  exit 1
                fi
                md=$(realpath "$input")
                resource_path=$(dirname "$md")
                if [ -z "$title" ]; then
                  title=$(basename "$md")
                  title=''${title%.*}
                fi
              fi

              if [ -z "$cache_dir" ]; then
                cache_dir="''${XDG_CACHE_HOME:-''${HOME:-$tmp/.home}/.cache}/mdkitty"
              fi

              md_hash_line=$(md5sum "$md")
              md_hash=''${md_hash_line%% *}
              key_file=$tmp/cache-key
              {
                echo "mdkitty-cache-v6"
                echo "markdown=$md_hash"
                echo "resource_path=$resource_path"
                echo "title=$title"
                echo "width=$width"
                echo "page_size=$page_size"
                echo "body_max_width=$body_max_width"
              } > "$key_file"
              cache_key_line=$(md5sum "$key_file")
              cache_key=''${cache_key_line%% *}
              cache_entry=$cache_dir/$cache_key
              cache_html=$cache_entry/document.html
              cache_pdf=$cache_entry/document.pdf
              cache_image=$cache_entry/document.png

              render_document() {
                local page_prefix
                page_prefix=$tmp/page

                pandoc \
                  --from markdown+smart \
                  --to html5 \
                  --standalone \
                  --embed-resources \
                  --mathml \
                  --metadata "pagetitle=$title" \
                  --resource-path="$resource_path:$(pwd)" \
                  --highlight-style=tango \
                  --css "$css" \
                  --output "$html" \
                  "$md"

                weasyprint --quiet "$html" "$pdf" >/dev/null
                pdftoppm -png -r 180 "$pdf" "$page_prefix" >/dev/null

                mapfile -t pages < <(find "$tmp" -maxdepth 1 -name 'page-*.png' -print | sort -V)
                if [ "''${#pages[@]}" -eq 0 ]; then
                  echo "mdkitty: no pages were rendered" >&2
                  exit 1
                fi

                magick "''${pages[@]}" -append -resize "$width"x "$image"
              }

              prune_cache() {
                local limit
                limit=''${MDKITTY_CACHE_LIMIT:-32}
                if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -lt 1 ]; then
                  return 0
                fi
                find "$cache_dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
                  | sort -rn \
                  | tail -n +"$((limit + 1))" \
                  | while IFS= read -r line; do
                      rm -rf "''${line#* }"
                    done
              }

              if [ "$cache" -eq 1 ] && [ -s "$cache_pdf" ] && [ -s "$cache_image" ]; then
                html=$cache_html
                pdf=$cache_pdf
                image=$cache_image
                touch "$cache_entry" "$cache_pdf" "$cache_image" 2>/dev/null || true
              else
                render_document
                if [ "$cache" -eq 1 ]; then
                  mkdir -p "$cache_entry"
                  cp "$html" "$cache_html"
                  cp "$pdf" "$cache_pdf"
                  cp "$image" "$cache_image"
                  prune_cache
                  html=$cache_html
                  pdf=$cache_pdf
                  image=$cache_image
                fi
              fi

              if [ -n "$out_dir" ]; then
                mkdir -p "$out_dir"
                cp "$html" "$out_dir/document.html"
                cp "$pdf" "$out_dir/document.pdf"
                cp "$image" "$out_dir/document.png"
              fi

              open_pdf() {
                local opened_pdf
                if [ "$cache" -eq 1 ]; then
                  opened_pdf=$pdf
                elif [ -n "$out_dir" ]; then
                  opened_pdf=$out_dir/document.pdf
                else
                  opened_pdf=$(mktemp "''${TMPDIR:-/tmp}/mdkitty.XXXXXX.pdf")
                  cp "$pdf" "$opened_pdf"
                fi
                open "$opened_pdf"
              }

              detect_window_size() {
                local rows_cols pixels rows cols px_w px_h
                if [ -e /dev/tty ]; then
                  rows_cols=$( (stty size < /dev/tty) 2>/dev/null || true )
                  pixels=$( (kitty +kitten icat --print-window-size < /dev/tty) 2>/dev/null || true )
                else
                  rows_cols=
                  pixels=
                fi

                if [[ "$rows_cols" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
                  rows=''${BASH_REMATCH[1]}
                  cols=''${BASH_REMATCH[2]}
                else
                  rows=
                  cols=
                fi

                if [[ "$pixels" =~ ^([0-9]+)x([0-9]+)$ ]]; then
                  px_w=''${BASH_REMATCH[1]}
                  px_h=''${BASH_REMATCH[2]}
                else
                  px_w=
                  px_h=
                fi

                if [ -n "$rows" ] && [ -n "$cols" ] && [ -n "$px_w" ] && [ -n "$px_h" ]; then
                  printf '%s,%s,%s,%s\n' "$cols" "$rows" "$px_w" "$px_h"
                else
                  printf '%s\n' "''${MDKITTY_WINDOW_SIZE:-100,40,1000,800}"
                fi
              }

              window_size_field() {
                local field value
                field=$1
                value=''${MDKITTY_WINDOW_SIZE:-100,40,1000,800}
                IFS=, read -r cols rows px_w px_h <<< "$value"
                case "$field" in
                  cols) printf '%s\n' "$cols" ;;
                  rows) printf '%s\n' "$rows" ;;
                  px_w) printf '%s\n' "$px_w" ;;
                  px_h) printf '%s\n' "$px_h" ;;
                esac
              }

              split_image_for_pager() {
                local image_w image_h cols rows px_w px_h cell_h max_cells max_chunk_h y h strip_dir display_px_w source_cell_h overlap overlap_display
                strip_dir=$tmp/strips
                mkdir -p "$strip_dir"

                image_w=$(magick identify -format '%w' "$image")
                image_h=$(magick identify -format '%h' "$image")
                cols=$(window_size_field cols)
                rows=$(window_size_field rows)
                px_w=$(window_size_field px_w)
                px_h=$(window_size_field px_h)

                if ! [[ "$rows" =~ ^[0-9]+$ ]] || [ "$rows" -lt 10 ]; then
                  rows=40
                fi
                if ! [[ "$px_h" =~ ^[0-9]+$ ]] || [ "$px_h" -lt "$rows" ]; then
                  px_h=$((rows * 20))
                fi
                if ! [[ "$px_w" =~ ^[0-9]+$ ]] || [ "$px_w" -lt 1 ]; then
                  px_w=$image_w
                fi

                cell_h=$((px_h / rows))
                if [ "$cell_h" -lt 8 ]; then
                  cell_h=16
                fi

                display_px_w=$px_w
                if [ "$image_w" -lt "$display_px_w" ]; then
                  display_px_w=$image_w
                fi
                if [ "$display_px_w" -lt 1 ]; then
                  display_px_w=$image_w
                fi

                source_cell_h=$((cell_h * image_w / display_px_w))
                if [ "$source_cell_h" -lt 1 ]; then
                  source_cell_h=1
                fi

                max_cells=$((rows - 3))
                if [ "$max_cells" -gt 240 ]; then
                  max_cells=240
                fi
                if [ "$max_cells" -lt 20 ]; then
                  max_cells=20
                fi

                max_chunk_h=$((max_cells * source_cell_h))
                overlap_display=''${MDKITTY_PAGER_OVERLAP_PX:-0}
                if ! [[ "$overlap_display" =~ ^[0-9]+$ ]]; then
                  overlap_display=0
                fi
                overlap=$((overlap_display * image_w / display_px_w))

                y=0
                while [ "$y" -lt "$image_h" ]; do
                  h=$max_chunk_h
                  if [ $((y + h)) -gt "$image_h" ]; then
                    h=$((image_h - y))
                  fi
                  strip=$strip_dir/strip-$(printf '%05d' "$y").png
                  magick "$image" -crop "''${image_w}x''${h}+0+''${y}" +repage "$strip"
                  printf '%s\n' "$strip"
                  if [ $((y + h)) -ge "$image_h" ]; then
                    break
                  fi
                  y=$((y + h - overlap))
                done
              }

              emit_kitty_stream() {
                local placeholder=''${1:-0}
                shift || true
                local separator=''${1:-1}
                shift || true
                local -a icat_args
                local item

                icat_args=(
                  +kitten icat
                  --stdin=no
                  --transfer-mode=stream
                  --align=center
                  --fit=width
                )
                if [ "$placeholder" -eq 1 ]; then
                  icat_args+=(--unicode-placeholder)
                fi
                if [ ! -t 1 ]; then
                  icat_args+=(--use-window-size="''${MDKITTY_WINDOW_SIZE:-100,40,1000,800}")
                fi

                if [ "$#" -eq 0 ]; then
                  set -- "$image"
                fi

                for item in "$@"; do
                  kitty "''${icat_args[@]}" "$item"
                  if [ "$separator" -eq 1 ]; then
                    printf '\n'
                  fi
                done
              }

              emit_pager_stream() {
                split_image_for_pager | while IFS= read -r strip; do
                  emit_kitty_stream 1 0 "$strip"
                done
              }

              pager_transcript_cache_path() {
                local key_file key_line key
                key_file=$tmp/pager-cache-key
                {
                  echo "mdkitty-pager-cache-v1"
                  echo "window=$MDKITTY_WINDOW_SIZE"
                  echo "overlap=''${MDKITTY_PAGER_OVERLAP_PX:-0}"
                } > "$key_file"
                key_line=$(md5sum "$key_file")
                key=''${key_line%% *}
                printf '%s\n' "$cache_entry/pager-$key.kitty"
              }

              case "$mode" in
                view)
                  emit_kitty_stream 0 1
                  if [ -n "$out_dir" ]; then
                    echo "Saved render artifacts to $out_dir" >&2
                  fi
                  ;;
                pager)
                  MDKITTY_WINDOW_SIZE=$(detect_window_size)
                  export MDKITTY_WINDOW_SIZE
                  transcript=$(pager_transcript_cache_path)
                  if [ "$cache" -eq 1 ] && [ -s "$transcript" ]; then
                    touch "$transcript" 2>/dev/null || true
                    less -r "$transcript"
                  else
                    tmp_transcript=$tmp/markdown.kitty
                    set +e
                    emit_pager_stream | tee "$tmp_transcript" | less -r
                    pipeline_status=("''${PIPESTATUS[@]}")
                    set -e
                    if [ "$cache" -eq 1 ] && [ "''${pipeline_status[0]}" -eq 0 ] && [ -s "$tmp_transcript" ]; then
                      mkdir -p "$cache_entry"
                      cp "$tmp_transcript" "$transcript"
                    fi
                  fi
                  if [ -n "$out_dir" ]; then
                    echo "Saved render artifacts to $out_dir" >&2
                  fi
                  ;;
                pdf)
                  open_pdf
                  if [ -n "$out_dir" ]; then
                    echo "Saved render artifacts to $out_dir" >&2
                  fi
                  ;;
                stdout)
                  emit_kitty_stream 0 1
                  ;;
              esac
            '';
          };

          default = self.packages.${system}.mdkitty;
        }
      );

      apps = forAllSystems (system: {
        mdkitty = {
          type = "app";
          program = "${self.packages.${system}.mdkitty}/bin/mdkitty";
        };
        default = self.apps.${system}.mdkitty;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              self.packages.${system}.mdkitty
              pkgs.imagemagick
              pkgs.pandoc
              pkgs."poppler-utils"
              pkgs.python3Packages.weasyprint
              pkgs.kitty
              pkgs.less
            ];
          };
        }
      );
    };
}
