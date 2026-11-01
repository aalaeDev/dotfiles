// Preloaded by the vlc wrapper. VLC's seek bar installs its own QStyle, which paints a hardcoded
// blue fill and an outline and hides it from the stylesheet. Refusing that one setStyle() leaves
// the slider on the application style, so vlc.qss draws it instead.
#include <QStyle>
#include <QWidget>
#include <dlfcn.h>
#include <stdlib.h>

__attribute__((constructor)) static void dontLeakIntoChildren()
{
    unsetenv("LD_PRELOAD");
}

void QWidget::setStyle(QStyle *style)
{
    using SetStyle = void (*)(QWidget *, QStyle *);
    static auto real = reinterpret_cast<SetStyle>(dlsym(RTLD_NEXT, "_ZN7QWidget8setStyleEP6QStyle"));
    if (!inherits("SeekSlider"))
        real(this, style);
}
