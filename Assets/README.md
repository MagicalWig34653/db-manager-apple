# DB-Manager-Appicon

Eigener AGPL-3.0-only-Vektorentwurf: Datenbankkörper und separate Tabellenebene,
kein Text und keine fremden Markenzeichen. Zwei SVG-Layer in einem echten
Icon-Composer-Dokument AppIcon.icon, Hintergrund als Composer-Füllung. Keine
flache Bitmap als Layerprojekt ausgegeben. Icon Composer27.1/129 aus Xcode27.1.

Die Struktur folgt der installierten Apple-Multiplatform-Iconvorlage; eigene
Gruppen/Layers mit dem tatsächlichen Composer-Renderer geprüft. Apple veröffentlicht
keine stabile JSON-Schemagarantie; deshalb ist die konkrete Toolvalidierung maßgeblich.

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" Assets/AppIcon.icon --export-image --output-file /tmp/db-manager-icon.png --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

Xcode referenziert AppIcon.icon als Ressource und AppIcon als Appiconnamen.
[Apple-Anleitung](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer),
[Icon Composer](https://developer.apple.com/icon-composer/).
Geräte-/Home-Screen-Sichtprüfung separat offen; Exportvorschauen sind keine
installierte Gerätesimulation. Keine Fremdassets oder neuen Lizenzabhängigkeiten.
