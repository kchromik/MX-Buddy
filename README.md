# MX Buddy

Native macOS-Menüleisten-App für die Logitech MX Master 3S und MX Master 4 über Bluetooth. Das Daumenrad wechselt zwischen Desktops und Vollbild-Apps. In „Belegungen öffnen“ lässt sich für jede Taste und Radrichtung eine Systemaktion oder ein eigenes Tastenkürzel wählen.

## Verwenden

1. Die Maus über Bluetooth mit dem Mac verbinden und MX Buddy öffnen. Das Fenster zeigt Modell und Verbindungsstatus.
2. Über „Systemeinstellungen öffnen“ die Bedienungshilfen und die Eingabeüberwachung für MX Buddy aktivieren. Fehlt die App in der Liste der Eingabeüberwachung, dort über **+** die installierte App hinzufügen. „Installierte App im Finder zeigen“ führt zur richtigen Kopie. Einen von macOS angeforderten Neustart der App bestätigen.
3. In der Seitenansicht oder Draufsicht einen Punkt auf der Maus anklicken. Rechts die Aktion für die Taste oder Bewegungsrichtung auswählen. „Eigenes Tastenkürzel“ nimmt die gedrückte Kombination auf. Die Einstellungen gelten sofort und werden pro Modell gespeichert.
4. Mit **Bei der Anmeldung starten** MX Buddy als macOS-Anmeldeobjekt ein- oder ausschalten. Beim automatischen Start läuft die App in der Menüleiste. Das Einstellungsfenster lässt sich dort über „Belegungen öffnen“ aufrufen.

„Space nach links/rechts“ und „Mission Control“ verwenden die in macOS hinterlegten Tastenkürzel. Diese unter **Systemeinstellungen → Tastatur → Tastaturkurzbefehle → Mission Control** aktivieren.

## Tasten und Gesten

Beide Modelle unterstützen Daumenrad, Hauptscrollrad, Links-, Rechts- und Mittelklick, Vor, Zurück, Gestentaste und Radmodus-Taste. Bei der MX Master 4 ist die drückbare Daumenfläche separat belegbar. Die Taste zur Gerätewahl an der Unterseite wechselt den verbundenen Host.

Im Gestenrad steht die Mitte für einen Druck auf die Gestentaste. Einer der vier Pfeile wählt die Bewegung bei gehaltener Taste aus. Die Aktionskarte darunter zeigt die aktuelle Belegung und öffnet die verfügbaren Aktionen. Sobald eine davon belegt ist, übernimmt MX Buddy die gesamte Gestentaste. Die übrigen Richtungen erscheinen als „Unbelegt“. Sobald alle fünf Einträge wieder frei sind, gibt MX Buddy die Gestentaste an das Gerät zurück.

Im Menüleistensymbol lassen sich alle Belegungen pausieren. **⌃⌥⇧R** stellt systemweit das native Verhalten beider Mäuse wieder her, auch für den Linksklick. Dieser Befehl entfernt die gespeicherten Belegungen, einschließlich des voreingestellten Space-Wechsels.

Sendet die Maus bereits Logitech-Ereignisse für Options+, nutzt MX Buddy diese auch. Lösen beide Apps eine Aktion aus, die zusätzliche Aktion für das betreffende Bedienelement in Options+ deaktivieren. Direkte Bluetooth-Verbindungen sind der unterstützte Gerätepfad. Ein Bolt-Empfänger benötigt eine andere Adressierung.

## Entwicklung

Das Projekt benötigt macOS 14 oder neuer und Xcode mit Swift 6. Für lokale Builds auf einem anderen Mac das eigene Signaturteam wählen.

```sh
xcodebuild -scheme 'MX Buddy' -configuration Release build
xcodebuild -scheme 'MX Buddy' -destination 'platform=macOS' test
```

IOKit erkennt die Maus und überträgt HID++-Nachrichten für Daumenrad und Sondertasten. Ein Quartz-Ereignisfilter verarbeitet reguläre Klicks und Scrollbewegungen anhand der Gerätekennung. Belegungen und Kürzel liegen lokal in UserDefaults. Die native Oberfläche verwendet Outfit und das [zentrale Branding](https://github.com/kchromik/Branding).

Die lokal eingebundenen Modellansichten stammen aus den Logitech-Produktgalerien. [MX Master 3S](https://www.logitech.com/en-us/shop/p/mx-master-3s) · [MX Master 4](https://www.logitech.com/en-us/shop/p/mx-master-4)
