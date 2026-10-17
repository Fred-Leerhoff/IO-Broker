# ioBroker auf QNAP TS-1273AU

Versionierte Docker-Compose-Konfiguration fuer QNAP Container Station 3.

## Architektur
- **QNAP TS-1273AU:** ioBroker fuer Visualisierung, uebergeordnete Szenarien und Daten.
- **Raspberry Pi 3 / Homematic:** Steuerung von Rollos und Heizung bleibt autark, auch bei NAS-Ausfall.
- **Fernzugriff:** ausschliesslich ueber VPN; keine Internet-Portfreigabe.

## Version
`buanet/iobroker:v12.0.0` (Node.js 24, geprueft 17.10.2026). Ein festes Versionstag verhindert ungeplante Hauptversionswechsel.

## Installation
1. Im QNAP-Dateimanager unter der Freigabe `Container` den Ordner `iobroker/data` anlegen. Den Pfad `/share/Container/iobroker/data` auf dem NAS verifizieren und Schreibrechte fuer den Container sicherstellen.
2. **Container Station 3 > Anwendungen > Erstellen**: Inhalt von [compose.yaml](compose.yaml) einfuegen.
3. Nach Start im LAN `http://<NAS-IP>:18081` aufrufen, Einrichtungsassistent abschliessen und Adminzugang absichern.
4. NAS-Firewall auf LAN/VPN begrenzen; **keine** Router-Portweiterleitung einrichten.
5. Persistente Daten liegen im Bind Mount und bleiben bei Container-Recreate erhalten.

## Homematic-Integration
Der Container nutzt zunaechst Docker-Bridge-Netzwerk und veroeffentlicht nur Port 18081.
**hm-rpc braucht je nach Konfiguration zusaetzliche Rueckrufports und eine erreichbare ioBroker-Adresse.** Vor Einrichtung RPC-/Callback-Ports, Netzsegmente und QNAP-Firewall pruefen. Host/macvlan nicht ohne Netzwerkplanung aktivieren.

## Wartung und Backup
- Vor Updates Backup mit ioBroker Backitup oder bei gestopptem Container konsistente Sicherung des gesamten Datenordners erstellen, moeglichst zusaetzlich ausserhalb des NAS.
- Versionswechsel in `compose.yaml` bewusst vornehmen. Adapter-Kompatibilitaet und Release Notes kontrollieren.
- Logs in Container Station lesen und Volume-Schreibrechte pruefen.
- Keine Secrets oder Laufzeitdaten in Git committen.

## Status
Docker-Konfiguration vorbereitet, **nicht auf dem QNAP installiert**. Homematic-Anbindung folgt nach Netzwerkkonfiguration.

## Quellen
- https://hub.docker.com/r/buanet/iobroker/tags
- https://docs.buanet.de/de/iobroker-docker-image/docs/
