#!/bin/bash
# BNAsec-Arch: install dirb (Debian) + wpscan (Kali pool) into the airootfs.
# (Neither is in Arch repos; v1.0.0 accidentally shipped without them.)
# Merge rules:
#   - never overwrite an existing airootfs file (Arch libs always win)
#   - skip Debian/Kali glibc-core libs (Arch's are ABI-compatible here)
#   - flatten /usr/lib/x86_64-linux-gnu + /lib/... into /usr/lib
set -e
source /home/z/my-project/arch-build/env.sh
R=$AIROOTFS
ST=$AB/extratools
QL=$ST/q.list
mkdir -p $ST && cd $ST
rm -rf x q.list; mkdir -p x q.list

SKIP_RE='^lib(c|m|dl|pthread|rt|resolv|nsl|util|crypt|anl|BrokenLocale)\.so|ld-linux|libpthread-|libnss_(dns|files|compat)|libm-'
SKIP_PKGS='^(libc6|libgcc-s1|libgcc1|libstdc\+\+6|debconf|dpkg|perl-base|gcc-.*-base|libselinux1|libpcre2-8-0|libsystemd0|libudev1|zlib1g)$'

copy_merge() { # copy_merge <src-under-x> <dest-under-R>
  local src="x/$1" dst="$R/$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  (cd "$src" && find . -mindepth 1) | while read -r rel; do
    local s="$src/$rel" d="$dst/${rel#./}"
    if [ -L "$s" ]; then
      [ -e "$d" ] || { mkdir -p "$(dirname "$d")"; cp -P "$s" "$d"; }
    elif [ -d "$s" ]; then
      mkdir -p "$d"
    else
      case "$(basename "$d")" in
        *.md5sums|*.postinst|*.postrm|*.preinst|*.prerm|*.list|*.conffiles|*.control) continue ;;
      esac
      if echo "$(basename "$d")" | grep -qE "$SKIP_RE"; then continue; fi
      [ -e "$d" ] && continue
      mkdir -p "$(dirname "$d")"; cp -p "$s" "$d"
    fi
  done
}

merge_x() {
  copy_merge usr/bin usr/bin
  copy_merge usr/games usr/bin
  copy_merge usr/sbin usr/bin
  copy_merge usr/share usr/share
  copy_merge usr/lib/ruby usr/lib/ruby
  copy_merge usr/lib/x86_64-linux-gnu usr/lib
  copy_merge usr/lib/x86_64-linux-gnu/rubygems-integration/3.3.0 usr/lib/ruby/gems/3.3.0
  copy_merge lib/x86_64-linux-gnu usr/lib
  copy_merge usr/lib/rubygems usr/lib/rubygems
  copy_merge etc etc
}

mark() { echo x > "$QL/$1"; }
marked() { [ -e "$QL/$1" ]; }

########################################
echo "=== A) dirb (Debian) ==="
if apt-get download dirb 2>&1 | tail -1 && ls dirb_*.deb >/dev/null 2>&1; then
  for round in 1 2 3; do
    for f in dirb_*.deb libcurl3-gnutls_*.deb; do
      [ -e "$f" ] || continue
      DEPS=$(dpkg-deb -f "$f" Depends 2>/dev/null | tr ',' '\n' | sed 's/ ([^)]*)//g; s/^ *//; s/ *$//' | grep -v '^$' || true)
      for d in $DEPS; do
        echo "$d" | grep -qE "$SKIP_PKGS" && continue
        marked "$d" || { mark "$d"; apt-get download "$d" 2>/dev/null | tail -1 || true; }
      done
    done
  done
  for f in dirb_*.deb libcurl*.deb; do [ -e "$f" ] && dpkg -x "$f" x/; done
  merge_x
  echo "  dirb merged"
else
  echo "  dirb download FAILED"
fi

########################################
echo "=== B) wpscan (Kali pool) ==="
KD=$ST/kali; mkdir -p "$KD"
IDX="$KD/Packages.gz"
for u in "https://kali.download/kali/dists/kali-rolling/main/binary-amd64/Packages.gz" \
         "http://http.kali.org/kali/dists/kali-rolling/main/binary-amd64/Packages.gz"; do
  curl -fsSL -o "$IDX" "$u" 2>/dev/null && break
done
if [ -s "$IDX" ]; then
  zcat "$IDX" > "$KD/Packages"
  resolve_kali() { # resolve_kali <pkgname> -> echoes deb URL (first hit in index)
    awk -v p="Package: $1" '
      $0==p {inpkg=1}
      inpkg && /^Filename:/ {print "http://http.kali.org/kali/" $2; exit}
      /^$/ {inpkg=0}' "$KD/Packages"
  }
  dl_kali() { # dl_kali <pkgname> -> extract into x/ ; returns 0 on success
    marked "kali:$1" && return 0
    mark "kali:$1"
    local url=$(resolve_kali "$1")
    [ -n "$url" ] || { echo "  kali: no index entry for $1"; return 1; }
    local f="$KD/$(basename "$url")"
    curl -fsSL -o "$f" "$url" 2>/dev/null || { echo "  kali: download failed $1"; return 1; }
    dpkg -x "$f" x/
    echo "  kali: $1 OK ($(du -h "$f" | cut -f1))"
    return 0
  }
  # wpscan CLI was dropped from kali-rolling; install its framework
  # (ruby-cms-scanner + full ruby runtime, all precompiled debs) instead,
  # then layer the pure-ruby wpscan gem (3.8 line: no ferrum/native deps)
  # from rubygems.org on top.
  dl_kali ruby-full || true
  dl_kali ruby3.3 || true
  dl_kali ruby-rubygems || true
  dl_kali ruby-cms-scanner || true
  for round in 1 2 3 4 5; do
    for f in "$KD"/*.deb; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in ruby3.3_*|ruby-full_*|ruby-rubygems_*|ruby-cms-scanner_*|ruby-*|libyaml-*|libruby*|ruby) ;; *) continue ;; esac
      DEPS=$(dpkg-deb -f "$f" Depends 2>/dev/null | tr ',' '\n' | sed 's/ ([^)]*)//g; s/^ *//; s/ *$//' | grep -v '^$' || true)
      for d in $DEPS; do
        echo "$d" | grep -qE "$SKIP_PKGS" && continue
        d=$(echo "$d" | sed 's/ .*//; s/|.*//; s/ .*//')
        dl_kali "$d" || true
      done
    done
  done
  merge_x
  echo "  ruby stack merged; installing wpscan gem"
  # no chroot exists: run with CWD=$R + relative paths so gem resolves
  # inside the airootfs; give DNS a real resolv.conf (build symlinks dangle)
  rm -f "$R/etc/resolv.conf" && cp /etc/resolv.conf "$R/etc/resolv.conf"
  mkdir -p "$R/var/lib/gems/3.3.0/bin"
  GEMRUN='usr/bin/ruby -I usr/lib/ruby/3.3.0 -I usr/lib/ruby/3.3.0/x86_64-linux-gnu -I usr/lib/ruby/vendor_ruby -I usr/lib/ruby/vendor_ruby/3.3.0 -I usr/lib/ruby/vendor_ruby/3.3.0/x86_64-linux-gnu -I usr/lib/ruby/gems/3.3.0/gems'
  GENV="GEM_PATH=usr/lib/ruby/gems/3.3.0:var/lib/gems/3.3.0 GEM_HOME=var/lib/gems/3.3.0"
  # wpscan 3.8 + full pure-ruby dep set from rubygems.org (Kali debs cover
  # the native ones: yajl/ffi/nokogiri); --ignore-dependencies avoids
  # native builds; per-gem version pins match wpscan 3.8 / cms_scanner 0.15
  gem_i() { # gem_i <gem> [version-constraint]
    local g="$1" v="$2"
    ( cd "$R" && GEM_PATH=usr/lib/ruby/gems/3.3.0:var/lib/gems/3.3.0 GEM_HOME=var/lib/gems/3.3.0 \
      arch_run2 "$R" $GEMRUN usr/bin/gem install "$g" ${v:+--version "$v"} \
      --no-document --ignore-dependencies --install-dir var/lib/gems/3.3.0 2>&1 | tail -1 )
  }
  gem_i wpscan '~> 3.8'
  gem_i activesupport
  gem_i i18n; gem_i concurrent-ruby; gem_i tzinfo; gem_i minitest; gem_i base64
  gem_i logger; gem_i mutex_m; gem_i securerandom; gem_i drb; gem_i connection_pool
  gem_i benchmark; gem_i strscan; gem_i date; gem_i timeout; gem_i English
  gem_i ostruct; gem_i rubyzip; gem_i ruby-progressbar; gem_i sys-proctable
  gem_i mini_portile2; gem_i ethon '< 0.17'; gem_i typhoeus '< 1.5'
  gem_i addressable '< 2.9'; gem_i public_suffix '< 6.1'
  gem_i cms_scanner; gem_i opt_parse_validator; gem_i get_process_mem
  gem_i webrick; gem_i xmlrpc; gem_i ffi
  # spec fixes: get_process_mem/activesupport declare bigdecimal, which is a
  # bundled stdlib here (flat .so) -> drop from specs; also kill any 4.x wpscan
  rm -rf "$R"/var/lib/gems/3.3.0/specifications/wpscan-4.*.gemspec "$R"/var/lib/gems/3.3.0/gems/wpscan-4.*
  cat > "$ST/fixspec.rb" << 'RUBY'
require 'rubygems'
spec = Gem::Specification.load(ARGV[0])
spec.dependencies.reject! { |d| d.name == 'bigdecimal' }
File.write(spec.spec_file, spec.to_ruby_for_cache)
puts "  spec fixed: #{spec.full_name}"
RUBY
  for spec in "$R"/var/lib/gems/3.3.0/specifications/activesupport-*.gemspec "$R"/var/lib/gems/3.3.0/specifications/get_process_mem-*.gemspec; do
    [ -e "$spec" ] && ( cd "$R" && arch_run2 "$R" usr/bin/ruby -I usr/lib/ruby/3.3.0 -I usr/lib/ruby/vendor_ruby -I usr/lib/ruby/vendor_ruby/3.3.0 "$ST/fixspec.rb" "${spec#$R/}" ) || true
  done
  # fiddle: stdlib .so present, gem missing -> stub spec
  [ -f "$R/usr/lib/ruby/3.3.0/fiddle.so" ] && cat > "$ST/mkstub.rb" << 'RUBY'
require 'rubygems'
s = Gem::Specification.new
s.name = ARGV[0]
s.version = Gem::Version.new(ARGV[1])
s.platform = Gem::Platform::RUBY
s.summary = 'stdlib stub'
s.files = []
File.write(File.join(Gem.dir, 'specifications', s.full_name + '.gemspec'), s.to_ruby_for_cache)
puts "  stub #{s.full_name}"
RUBY
  [ -f "$R/usr/lib/ruby/3.3.0/fiddle.so" ] && ( cd "$R" && GEM_HOME=var/lib/gems/3.3.0 arch_run2 "$R" usr/bin/ruby -I usr/lib/ruby/3.3.0 -I usr/lib/ruby/vendor_ruby -I usr/lib/ruby/vendor_ruby/3.3.0 "$ST/mkstub.rb" fiddle 1.1.8 ) || true
  # belt & suspenders: mirror var/lib gems into the vendor dir so any
  # default GEM_PATH sees everything
  cp -an "$R"/var/lib/gems/3.3.0/specifications/*.gemspec "$R/usr/lib/ruby/gems/3.3.0/specifications/" 2>/dev/null || true
  cp -an "$R"/var/lib/gems/3.3.0/gems/* "$R/usr/lib/ruby/gems/3.3.0/gems/" 2>/dev/null || true
  cp -p "$R/var/lib/gems/3.3.0/bin/wpscan" "$R/usr/bin/wpscan" 2>/dev/null && echo "  wpscan binstub installed"
else
  echo "  Kali index unreachable — wpscan skipped"
fi

########################################
echo "=== smoke test ==="
run_a() { arch_run2 "$R" "$@"; }
run_a usr/bin/dirb 2>&1 | head -2 || true
run_a usr/bin/ruby --version 2>&1 | head -1 || true
run_a usr/bin/wpscan --version 2>&1 | head -3 || true
ls "$R/usr/share/dirb/wordlists/" 2>/dev/null | head -3
echo "=== EXTRATOOLS DONE ==="
