# ioBroker auf QNAP TS-1273AU

ioBroker (Docker-Image `buanet/iobroker:v12.0.0`, Node.js 24, Stand 17.10.2026) wird als eigener Container auf dem QNAP betrieben.

## Architektur
- **QNAP TS-1273AU:** ioBroker fuer Visualisierung, uebergeordnete Szenarien und Daten.
- **Raspberry Pi 3 / Homematic:** Steuerung von Rollos und Heizung bleibt autark, auch bei NAS-Ausfall.
- **Fernzugriff:** nur ueber VPN, keine Internet-Portfreigabe.

## Deployment
Wir verwenden den QNAP **Pull-Deployer wie bei MyMoMa**. Der NAS-Host prueft alle fuenf Minuten ausschliesslich den autorisierten Branch `deploy/qnap` und startet nach Freigabe die Compose-Konfiguration selbststaendig.

**[Anleitung fuer die einmalige Ersteinrichtung, Updates und Fehlerdiagnose](docs/QNAP_DEPLOYMENT.md)**

Nach der Ersteinrichtung sind keine manuellen Aktionen in der Container Station mehr notwendig. Fuer das erste Aufsetzen braucht es einmalig eine lokale SSH-Sitzung auf dem QNAP, weil GitHub keinen direkten Zugriff auf die NAS-Docker-Engine besitzt.

## Dateien
- `compose.yaml`: ioBroker-Container, Port `18081:8081`, Daten unter `/share/Container/iobroker/data`.
- `scripts/install_qnap_deployer.sh`: einmalige Einrichtung des QNAP-Cronjobs.
- `scripts/qnap_deploy.sh`: versionskontrollierter Deploy mit Check, konsistentem Backup und Rollback-Versuch.
- `docs/QNAP_DEPLOYMENT.md`: Einrichtung und Betrieb.

## Homematic
Bridge-Netzwerk ist der sichere Startpunkt. Der hm-rpc-Adapter benoetigt fuer Homematic-RPC Rueckrufe unter Umstaenden zusaetzliche Ports und eine erreichbare Callback-IP; das legen wir mit dem Netzwerkkonzept fest. RaspberryMatic bleibt autark.

## Status
**GitHub-Konfiguration und Deploy-Skripte vorbereitet, nicht auf dem QNAP installiert.** Nur freigegebene Commits auf `deploy/qnap` koennen ausgerollt werden.

## Quellen
- https://hub.docker.com/r/buanet/iobroker/tags
- https://docs.buanet.de/de/iobroker-docker-image/docs/
