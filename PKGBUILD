# Maintainer: TiniTinyTerminator
pkgname=omarchy-plugin-odrive
_pkgname=odrive
pkgver=1.0.0
pkgrel=1
pkgdesc="Unified Cloud Drive Manager for Omarchy Linux — mount and manage Google Drive, OneDrive, Nextcloud, and more"
arch=('any')
url="https://github.com/TiniTinyTerminator/ODrive"
license=('MIT')
depends=('rclone' 'fuse3' 'python')
optdepends=(
    'omarchy: desktop environment and bar widget integration'
)
provides=('odrive')
conflicts=('odrive')
source=()
sha256sums=()

package() {
    cd "$startdir"

    # Install Omarchy plugin directory
    local plugin_dir="$pkgdir/usr/share/omarchy/plugins/ttt.odrive"
    install -d "$plugin_dir"
    cp -r manifest.json ui bin lib assets "$plugin_dir/"
    chmod +x "$plugin_dir/bin/odrive"

    # Install global CLI launcher
    install -d "$pkgdir/usr/bin"
    ln -sf "/usr/share/omarchy/plugins/ttt.odrive/bin/odrive" "$pkgdir/usr/bin/odrive"

    # Install user systemd service
    install -Dm644 systemd/odrive-automount.service "$pkgdir/usr/lib/systemd/user/odrive-automount.service"

    # Install documentation and license
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
}
