# Applies a new matugen.colors while Krita runs. Krita caches a scheme once it has parsed it,
# even across theme switches, so this reads the file itself and sets the palette
from configparser import ConfigParser

from krita import Extension

try:
    from PyQt6.QtCore import QFileSystemWatcher, Qt, QTimer
    from PyQt6.QtGui import QColor, QPalette
    from PyQt6.QtWidgets import QApplication
except ImportError:
    from PyQt5.QtCore import QFileSystemWatcher, Qt, QTimer
    from PyQt5.QtGui import QColor, QPalette
    from PyQt5.QtWidgets import QApplication

THEME = "Matugen"

# Palette role, then the section and key that KColorScheme takes it from
ROLES = {
    QPalette.ColorRole.WindowText: ("Window", "ForegroundNormal"),
    QPalette.ColorRole.Base: ("View", "BackgroundNormal"),
    QPalette.ColorRole.AlternateBase: ("View", "BackgroundAlternate"),
    QPalette.ColorRole.Text: ("View", "ForegroundNormal"),
    QPalette.ColorRole.ButtonText: ("Button", "ForegroundNormal"),
    QPalette.ColorRole.Highlight: ("Selection", "BackgroundNormal"),
    QPalette.ColorRole.HighlightedText: ("Selection", "ForegroundNormal"),
    QPalette.ColorRole.ToolTipBase: ("Tooltip", "BackgroundNormal"),
    QPalette.ColorRole.ToolTipText: ("Tooltip", "ForegroundNormal"),
    QPalette.ColorRole.Link: ("View", "ForegroundLink"),
    QPalette.ColorRole.LinkVisited: ("View", "ForegroundVisited"),
}
DISABLED_TEXT = (
    QPalette.ColorRole.WindowText,
    QPalette.ColorRole.Text,
    QPalette.ColorRole.ButtonText,
)


class MatugenLive(Extension):
    def setup(self):
        self.path = Application.getAppDataLocation() + "/color-schemes/matugen.colors"
        self.watcher = QFileSystemWatcher([self.path], self)
        # matugen may write in several steps, so wait for it to finish
        self.timer = QTimer(self)
        self.timer.setSingleShot(True)
        self.timer.setInterval(300)
        self.timer.timeout.connect(self.apply)
        self.watcher.fileChanged.connect(lambda _: self.timer.start())

    def createActions(self, window):
        pass

    def apply(self):
        # A replaced file drops out of the watch list
        if self.path not in self.watcher.files():
            self.watcher.addPath(self.path)
        actions = Application.action("theme_menu").menu().actions()
        if any(a.isChecked() and a.text().replace("&", "") == THEME for a in actions):
            palette = self.palette()
            QApplication.setPalette(palette)
            # Widgets that set their own palette ignore the application's
            for widget in QApplication.allWidgets():
                if widget.testAttribute(Qt.WidgetAttribute.WA_SetPalette):
                    widget.setPalette(palette)
            # Lets the welcome page, canvas and dockers rebuild from the new palette
            for window in Application.windows():
                window.themeChanged.emit()

    def palette(self):
        scheme = ConfigParser(interpolation=None, strict=False)
        scheme.optionxform = str
        scheme.read(self.path)

        def color(section, key):
            return QColor(*map(int, scheme[f"Colors:{section}"][key].split(",")[:3]))

        # This constructor also derives the bevel shades from the button color
        palette = QPalette(color("Button", "BackgroundNormal"), color("Window", "BackgroundNormal"))
        for role, (section, key) in ROLES.items():
            palette.setColor(role, color(section, key))
        for role in DISABLED_TEXT:
            palette.setColor(QPalette.ColorGroup.Disabled, role, color("Window", "ForegroundInactive"))
        return palette
