# Föreläsning — installation för testare

Tack för att du testar. Appen spelar in en lektion, skriver ut talet till text
**på din egen enhet** och gör ett underlag som du kan klistra in i
skolplattformen.

## Innan du börjar

- **Ljud och text stannar på enheten.** Inget laddas upp om du inte själv
  väljer en molnleverantör under Inställningar.
- **Modellerna laddas ned första gången du använder appen** — räkna med
  ~400 MB för tal och ~1,1 GB för sammanfattningen. Väljer du de större
  modellerna blir det upp till ~5,6 GB. Gör det på wifi, inte på lektionen.
- Ha **8 GB ledigt** på enheten för säkerhets skull.
- Appen är svensk och förväntar sig svenskt tal.

Du behöver godkänna mikrofonen första gången du trycker på spela in.

---

## Windows

1. Kör `Forelasning-1.0.0-windows-x64-setup.exe`.
2. Windows säger troligen **"Windows SmartScreen förhindrade att en okänd app
   startades"**. Det är väntat — installationsfilen är inte köpsignerad ännu.
   Klicka **Mer information** → **Kör ändå**.
3. Installationen kräver **inte** administratör. Appen hamnar under din egen
   användare och startas från Startmenyn som *Föreläsning*.

Vill du hellre slippa installera: packa upp `Forelasning-1.0.0-windows-x64.zip`
och kör `lecture_local.exe` direkt ur mappen.

Avinstallera via *Inställningar → Appar → Föreläsning*. Dina inspelningar och
underlag ligger kvar.

---

## Android

APK:en installeras vid sidan av Play — den ligger inte i butiken.

1. Ta **`Forelasning-1.0.0-android-arm64-v8a.apk`**. Det är rätt fil för i
   stort sett alla telefoner sålda de senaste åtta åren.
   - Väldigt gammal telefon? Prova `armeabi-v7a`.
   - Emulator på dator? `x86_64`.
2. Öppna filen i Filer eller nedladdningslistan.
3. Android frågar om appen får installera okända appar — säg ja för den app du
   öppnade filen från (oftast Files eller Chrome). Du kan slå av det efteråt.
4. **Play Protect** kan varna för att utvecklaren är okänd. Välj
   *Installera ändå*.

Telefonen behöver ligga still och nära dig under lektionen. Starta inspelningen,
lägg undan telefonen, stoppa när du är klar.

---

## Linux (Ubuntu 22.04 eller nyare, 64-bit x86)

```bash
sudo apt install ./forelasning_1.0.0-1_amd64.deb
```

`apt` drar in det som behövs, inklusive `pulseaudio-utils` — utan det
misslyckas inspelningen i samma sekund du trycker på start.

Starta *Föreläsning* från applikationsmenyn, eller `forelasning` i terminalen.

Avinstallera med `sudo apt remove forelasning`.

Tre saker att känna till:

- **Ubuntu 22.04 eller nyare** (Debian 12 och nyare fungerar också). Paketet
  säger ifrån vid installation om systemet är för gammalt, i stället för att gå
  sönder först när du ber om ett underlag.
- **Bara x86_64.** En arm64-dator (t.ex. en Raspberry Pi eller en ARM-laptop)
  kan inte köra den lokala sammanfattningen.
- **Ingen delningsruta.** På Linux finns ingen systemdelning att prata med, så
  använd **Kopiera** och klistra in i skolplattformen. Knappen *Dela* säger
  ifrån och hänvisar till Kopiera.

---

## Om datorn är långsam

Sammanfattningen körs lokalt. Går den trögt: gå till **Inställningar** och välj
den mindre modellen (1,5B) i stället för 7B. På en dator utan grafikkort som
llama.cpp känner igen är 7B mycket långsam.

På Linux körs sammanfattningen alltid på processorn — inget grafikkort används,
inte heller ett NVIDIA-kort. Det är ett medvetet val: alternativet krävde
NVIDIAs drivrutiner för att appen ens skulle starta sammanfattningen. Välj 1,5B
så går det i rimlig takt.

## Vad jag vill veta

- Blev underlaget något du faktiskt hade kunnat publicera — eller fick du
  skriva om det?
- Hittade den datum, prov och uppgifter som du nämnde under lektionen?
- Hittade den på något som inte sades?
- Hur lång tid tog det från *stoppa* till färdigt underlag, och på vilken
  enhet?
- Kraschade något, och i så fall var i flödet?
