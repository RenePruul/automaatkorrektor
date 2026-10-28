# Automaatkorrektor

Automaatkorrektor kontrollib, kas kasutaja selgelt valitud tekst on eesti
keeles. Rakendus ei jälgi teksti taustal ega paranda ega asenda teksti. Iga
kontroll algab menüüriba toimingust või seadistatud kiirklahvist.

## Keeleteenus

Automaatkorrektor on eraldi töötava ühilduva keeleteenuse klient. Vaikimisi
aadress on `http://127.0.0.1:8000`, seega ei lahku valitud tekst sellest
Macist. Paigalda projekt `keele_tuvastaja` eraldi ja käivita see enne kliendi
kasutamist, näiteks:

```sh
cd /tee/keele_tuvastaja
.venv/bin/keele-api
```

Klient ei paigalda ega käivita Pythonit ega keeleteenust. Kohalik teenus peab
kuulama ainult loopback-liidesel. Kontrolli selle kättesaadavust käsuga
`curl --fail http://127.0.0.1:8000/health`.

Seadetes saab kasutada ka enda valitud HTTPS-kaugteenust. Sellisel teenusel on
iseseisev operaator ning valitud teksti käideldakse tema tingimuste järgi.
Enne valitud teksti lugemist kuvab klient normaliseeritud sihtkoha ja küsib
selle origin'i jaoks keelekontrolli nõusolekut. Keeldumisel ei saadeta midagi.
Skeemi, hosti või tegeliku pordi muutmisel küsitakse uus nõusolek. Salvestatud
nõusoleku saab seadetes tühistada. Kasuta ainult usaldusväärset teenust ning
ära vali kontrollimiseks paroole, saladusi või tundlikke isikuandmeid.

## Minimaalse DMG paigaldamine

See versioon vajab macOS 15 või uuemat. Versioon ei ole Developer ID-ga
allkirjastatud ega Apple'i notariseeritud, mistõttu võib macOS esmakordsel
avamisel kinnitust küsida.

1. Ava allalaaditud `.dmg` ja lohista `Automaatkorrektor.app` kausta
   `/Applications`.
2. Proovi paigaldatud rakendus avada. Kui macOS selle blokeerib, tee rakendusel
   Control-klõps, vali **Open** ja kinnita uuesti **Open**. Teise võimalusena
   ava pärast blokeeritud käivitust **System Settings → Privacy & Security**
   ning vali Automaatkorrektori juures **Open Anyway**.
3. Anna Automaatkorrektorile küsitud juurdepääs asukohas **System Settings →
   Privacy & Security → Accessibility**.
4. Käivita eraldi keeleteenus, vali toetatud väljal tekst ja kasuta menüüribal
   toimingut **Kontrolli valitud teksti** või seadistatud kiirklahvi.

Ära lülita Gatekeeperit kogu süsteemis välja. Minimaalsel versioonil puudub
automaatne uuendaja: sulge rakendus ja asenda kaustas `/Applications` olev vana
rakendus käsitsi uuega. Kuna ad-hoc-järk muutub iga väljalaskega, võib macOS
küsida Accessibility-luba uuesti. Kui kontroll on endiselt blokeeritud, eemalda
vana Automaatkorrektori kirje Accessibility-loendist, lisa uus rakendus, luba
see ja ava rakendus uuesti.

## Allalaaditud faili kontrollimine

Iga finaliseeritud väljalase sisaldab versiooniga DMG-d, selle faili
`.dmg.sha256` ja faili `.release-metadata.txt`. Laadi kõik kolm samasse kausta
ning käivita:

```sh
shasum -a 256 -c Automaatkorrektor-v0.1.0.dmg.sha256
cat Automaatkorrektor-v0.1.0.release-metadata.txt
git fetch --tags
git rev-parse 'v0.1.0^{commit}'
```

Kontrollsumma käsk peab kuvama `OK`. Metaandmete `Tag` peab vastama väljalaske
tägile, `Commit` peab võrduma käsu `git rev-parse` väljundiga ja `DMG-SHA256`
peab võrduma kontrollsummaga. Asenda `v0.1.0` allalaaditud versiooniga.

## macOS v0.1 ühilduvus

Klient toetab selgelt valitud teksti TextEditis ning Safari või Chrome'i
standardsetel teksti-, otsingu- ja `textarea`-väljadel, kui macOS esitab
fookuses oleva juhtelemendi standardse muudetava Accessibility-tekstiväljana.
Teiste rakenduste või suvaliste brauseriredaktorite tuge ei lubata.

Parooliväljad, veebiala või dokumendi valikud, `contenteditable`-alad,
kohandatud juhtelemendid ja suletud Accessibility-sobivusreeglitele mittevastavad
väljad lükatakse tagasi enne valitud teksti lugemist. Klient ei kasuta
lõikelauda, ei läbi rakenduse sisupuud ega kasuta varumeetodina privaatseid
tekstiosuti API-sid.

Need ühilduvuslubadused ei hõlma taustal jälgimist, automaatset parandamist,
suvalisi redaktoreid ega teksti teise rakendusse tagasi kirjutamist.

## Väljalasketõendid

Versiooni v0.1 väljalaskeväravas on täpselt 35 nõutavat kontrolli. Käivita
automaatsed kontrollid ja loo ainult metaandmeid sisaldav raport käsuga:

```sh
scripts/release-gate.sh
```

Värav piirab vormindus- ja Git-kontrollid kahe minutiga, fixture-testid viie
minutiga, Swift-testid kümne minutiga ning iga Xcode build'i 15 minutiga.
Ajalimiidi ületamine ebaõnnestab automaatkontrolli ja lõpetab käsu alamprotsessid.
Haldaja võib määrata positiivse `RELEASE_GATE_TIMEOUT_SECONDS` väärtuse ainult
valvuri enda testimiseks; väljalaskel kasutatakse dokumenteeritud piiranguid.

Käsk lõpetab olekukoodiga `2`, kuni mõni päris rakenduse või operatsioonisüsteemi
kontroll on ootel. Järgi [käsikontrolli juhendit](release/MANUAL-CHECKLIST.md),
hoia täidetud TSV-faili kaustas `.release-evidence/` ja anna see tagasi
argumendiga `--manual-evidence`. Valitud tekst ja privaatsusnäite väärtus ei
tohi kunagi sattuda TSV-faili ega raportisse.

AppKiti juhtelementide kontroll kasutab kaht eraldi pakitud ainult testimiseks
mõeldud rakendust. Käivita `scripts/run-native-ax-harness.sh` ja järgi juhendit.
Testirakendus kasutab päris Accessibility-lugejat täpse testhosti reeglistikuga,
ei kasuta võrku ning raporteerib ainult metaandmetega `PASS`/`FAIL` tulemusi.
Tootmisrakendus lükkab selle hosti endiselt tagasi ja toetab ainult kolme
dokumenteeritud rakendust.

Käsikontroll kasutab sõltuvusteta ja ainult loopback'il töötavat fixture'it
[`tools/language_api_stub.py`](tools/language_api_stub.py). See pakub juhitud
vastuseid, viivitust, ühildumatut vastust, serveriviga, päringute arvu ja
privaatsusnäite metaandmeid ilma valitud teksti salvestamata või logimata.
Tegemist on testitaristuga, mitte keeletuvastajaga.

Loo kandidaat puhtast tööpuust, mille `HEAD`-il on täpne väljalaske tägi.
Automaatsed kontrollid peavad läbima; käsitsi täidetavad read jäävad
ootuspäraselt olekusse `PENDING`:

```sh
scripts/build-release-candidate.sh --tag v0.1.0
```

Käsk ehitab ja kontrollib ad-hoc-allkirjastatud rakenduse ning kirjutab
kandidaadi DMG, kandidaadi metaandmed ja ootel tõendite raporti kausta
`.release-evidence/candidates/`. Lõplikku kontrollsummat selles etapis ei looda.

Kopeeri `release/manual-evidence.example.tsv` faili
`.release-evidence/manual.tsv`. Asenda kolm `Candidate-*` päiseväärtust
kandidaadi metaandmetega ja tee kõik käsikontrollid täpselt selle DMG-ga.
Finaliseeri alles pärast kõigi ridade läbimist:

```sh
scripts/finalize-release-dmg.sh \
  --candidate .release-evidence/candidates/Automaatkorrektor-v0.1.0.dmg \
  --manual-evidence .release-evidence/manual.tsv
```

Finaliseerimine nõuab kandidaadi tägi, commit'i ja SHA-256-ga seotud `READY`
tõendeid. Kandidaati kontrollitakse uuesti ilma seda ehitamata või selle baite
muutmata. Seejärel tõstetakse bait-baidilt identne lõplik DMG, kontrollsumma,
metaandmed ja `READY` raport kausta `.release-evidence/releases/`. Kumbki etapp
ei laadi GitHub Release'i üles, ei push'i tägi ega muuda välist teenust.

Kontrolli finaliseeritud väljundeid pärast edutamist, mitte käsitõendite või
finaliseerimise eeltingimusena:

```sh
shasum -a 256 -c \
  .release-evidence/releases/Automaatkorrektor-v0.1.0.dmg.sha256
cat .release-evidence/releases/Automaatkorrektor-v0.1.0.release-metadata.txt
git rev-parse 'v0.1.0^{commit}'
```

Kontrollsumma peab kuvama `OK`. Lõplike metaandmete `Tag` ja `Commit` peavad
vastama täpsele Git-tägile ja lahendatud commit'ile. `DMG-SHA256` peab võrduma
kontrollsumma ning kandidaadi metaandmete `Candidate-SHA256` väärtusega.
