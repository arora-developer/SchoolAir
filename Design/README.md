# Design sources

`render_school.py` draws the app icon: a rainbow gauge ring (270°, open at the bottom) with a
marker dot, and a graduation cap in Apple's blue gradient, on white. It needs Pillow
(`pip3 install pillow`) and `render_icons.py` next to it. Run it from this folder to regenerate the
options. `render_final.py` writes the shipping icon (light, dark and tinted variants) into
`SchoolAir/Assets.xcassets/AppIcon.appiconset/`.

`SchoolAir/Views/SplashView.swift` draws the same mark live in SwiftUI at launch.
