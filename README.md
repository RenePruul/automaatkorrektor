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

## Väljalaske loomine

Käivita automaatsed kontrollid puhtas Giti tööpuus:

```sh
scripts/release-gate.sh
```

Eduka kontrolli lõpus kuvatakse `Kõik automaatkontrollid läbitud.`

Seejärel järgi [käsikontrolli juhendit](release/MANUAL-CHECKLIST.md). See on
praktiline kontrollnimekiri, mitte eraldi tõendifail: tulemust ei pea TSV-sse
ega raportisse salvestama.

AppKiti juhtelementide kontroll kasutab kaht eraldi pakitud ainult testimiseks
mõeldud rakendust. Käivita `scripts/run-native-ax-harness.sh` ja järgi juhendit.
Testirakendus kasutab päris Accessibility-lugejat täpse testhosti reeglistikuga,
ei kasuta võrku ning raporteerib ainult metaandmetega `PASS`/`FAIL` tulemusi.
Tootmisrakendus lükkab selle hosti endiselt tagasi ja toetab ainult kolme
dokumenteeritud rakendust.

Käsikontroll kasutab sõltuvusteta ja ainult loopback'il töötavat testserverit
[`tools/language_api_stub.py`](tools/language_api_stub.py). See pakub juhitud
vastuseid, viivitust ja päringute arvu ilma valitud teksti salvestamata või
logimata.
Tegemist on testitaristuga, mitte keeletuvastajaga.

Loo puhtast tööpuust versioonisildile vastav DMG. Silt peab osutama täpselt
praegusele `HEAD` commit'ile. Kui sobivat silti veel pole, loo see enne DMG-d:

```sh
git status
git tag v0.1.0
scripts/build-release-dmg.sh --tag v0.1.0
```

Valmis fail asub siin:

```sh
.release-evidence/releases/Automaatkorrektor-v0.1.0.dmg
```

Loo GitHubis samale versioonisildile Release ja lisa sellele DMG käsitsi.
Skript ei push'i silti ega laadi faili GitHubi üles.
