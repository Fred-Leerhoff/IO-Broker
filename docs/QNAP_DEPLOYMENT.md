# QNAP Pull-Deployment fuer ioBroker

Wie bei MyMoMa bleibt das QNAP das Deployment-Ziel. GitHub speichert Quellkonfiguration und einen **explizit freigegebenen Deploy-Branch**; die QNAP ruft diesen Branch alle 5 Minuten selbst ab. Kein offener SSH-Port ins Internet, kein GitHub-Runner auf dem NAS, keine Secrets in GitHub.

## Stand und Voraussetzungen
- QNAP TS-1273AU, Container Station 3 mit `docker compose` (Compose V2).
- QNAP SSH-Zugang **nur aus dem LAN oder VPN** als admin/root zur einmaligen Einrichtung.
- Bestehende QNAP-Freigabe `/share/Container`; als Ziel wird `/share/Container/IO-Broker` benutzt.
- Freier Host-Port **18081**. Der Container bekommt den Namen `iobroker`.
- Das Repository `Fred-Leerhoff/IO-Broker` ist derzeit oeffentlich; deshalb ist lesender GitHub-Zugriff per HTTPS ohne Schluessel moeglich.

## Einmalige Ersteinrichtung

**Die folgenden Befehle einmalig im QNAP-SSH-Terminal als admin/root ausfuehren**. Vorher pruefen, dass `/share/Container/IO-Broker` noch nicht existiert und dort keine vorhandenen Daten liegen.

```sh
docker run --rm -v /share/Container:/workspace alpine/git clone --branch deploy/qnap --single-branch https://github.com/Fred-Leerhoff/IO-Broker.git /workspace/IO-Broker
sh /share/Container/IO-Broker/scripts/install_qnap_deployer.sh
```

Die Installation macht danach Folgendes:
1. `/share/Container/iobroker/data` fuer persistente Daten anlegen (nicht ins Repository).
2. Ein QNAP-Cron-Job alle 5 Minuten in `/etc/config/crontab` eintragen und neu laden.
3. Einmalig das Deploy-Skript starten. Dieses zieht `buanet/iobroker:v12.0.0` und startet den Container ueber `docker compose -p iobroker`.
4. Den Start pruefen. Status und Logs bleiben auf dem NAS unter `/share/Container/IO-Broker/runtime/deploy/`.

**Wichtig:** Das ist kein bereits erfolgtes NAS-Deployment. Ohne diesen einmaligen lokalen Bootstrap kann GitHub allein keine Container auf dem NAS starten.

## Pruefung nach dem Start

```sh
docker ps --filter name=iobroker
tail -n 50 /share/Container/IO-Broker/runtime/deploy/deploy.log
```

Im LAN `http://<NAS-IP>:18081` aufrufen. Admin-Zugang absichern und QNAP-Firewall auf LAN/VPN beschraenken; **keine direkte Internetfreigabe**.

## Freigabe und Updates
- Entwicklungsweg: `main -> Feature-Branch -> Pull Request -> Pruefung -> Merge`.
- Nur der Branch **`deploy/qnap`** ist deploybar, analog zu MyMoMas `deploy/paper`.
- Wird `deploy/qnap` auf einen neuen, freigegebenen Commit bewegt, zieht das NAS genau diesen SHA und startet die aktualisierte Konfiguration.
- Der Deployer verhindert parallele Ausfuehrungen, laedt das Image vor der Unterbrechung herunter und sichert bei Updates die **angehaltenen** ioBroker-Daten als `.tar.gz`.
- Bei Start-/HTTP-Fehlern versucht er ein Rollback auf den letzten funktionierenden Compose-Stand. **Daten werden nicht automatisch rueckgespielt**, denn ein neues Image kann Datenmigrationen ausloesen. Deshalb zusaetzliche NAS-externe Backups vor groesseren Versionen.
- Fehlerhafte SHAs werden nicht staendig erneut ausgerollt. Der naechste Deploy braucht eine neue Freigabe auf `deploy/qnap`.

## Grenzen und Sicherheitsregeln
- Ein bereits vorhandener, nicht von diesem Deployer verwalteter Container namens `iobroker` wird **nicht uebernommen oder geloescht**.
- Der Cronjob steuert nur `IO-Broker`, nicht MyMoMa oder andere QNAP-Container.
- Das Compose nutzt Bridge-Netzwerk; Homematic-hm-rpc-Rueckrufports muessen nach der Netzwerkplanung separat konfiguriert werden.
- Der ioBroker sollte Haussteuerung **nicht** zur Pflichtabhaengigkeit machen. RaspberryMatic steuert Rollos/Heizung weiterhin autonom.
- Im Public-Repo niemals Passwoerter, VPN-Konfiguration oder NAS-Laufzeitdaten speichern.
- `deploy/qnap` nicht fuer ungetestete Experimente vorwaertssetzen.

## Fehlerdiagnose und Entfernen
- Logs: `tail -n 100 /share/Container/IO-Broker/runtime/deploy/deploy.log`.
- Cronjob stoppen: in `/etc/config/crontab` die ioBroker-markierte Zeile entfernen; dann `crontab /etc/config/crontab` ausfuehren.
- Docker im NAS auf Wunsch stoppen: `docker compose -p iobroker -f /share/Container/IO-Broker/compose.yaml stop iobroker`.
- Daten **nicht** einfach loeschen: Sie liegen unter `/share/Container/iobroker/data`.

## Referenz
[MyMoMa Pull-Deployer](https://github.com/Fred-Leerhoff/MyMoMa/blob/main/docs/QNAP_PULL_DEPLOYER.md) und [ioBroker Docker-Image](https://hub.docker.com/r/buanet/iobroker/tags).
