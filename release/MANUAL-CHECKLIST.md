# macOS-i väljalaske käsikontroll

Tee enne GitHub Release'i loomist need praktilised kontrollid. Eraldi TSV-d,
raportit ega muud tõendifaili pole vaja. Kasuta ainult sünteetilist testteksti;
ära vali paroole, saladusi ega päris isikuandmeid.

## DMG loomine ja paigaldamine

Loo versioonisildile vastav DMG:

```sh
scripts/build-release-dmg.sh --tag v0.1.0
open .release-evidence/releases/Automaatkorrektor-v0.1.0.dmg
```

Lohista `Automaatkorrektor.app` kausta `/Applications` ja ava paigaldatud
rakendus. Kui Gatekeeper rakenduse blokeerib, kasuta Control-klõpsu kaudu
valikut **Open** või **System Settings → Privacy & Security → Open Anyway**.
Ära lülita Gatekeeperit kogu süsteemis välja.

Anna rakendusele **System Settings → Privacy & Security → Accessibility** luba.

## Kohalik testteenus

Käivita eraldi terminalis ainult loopback'il töötav testteenus:

```sh
AUTOMAATKORREKTOR_STUB_PORT=8000 \
AUTOMAATKORREKTOR_STUB_VERDICT=jah \
python3 tools/language_api_stub.py
```

Vajaduse korral käivita teenus uuesti väärtusega `ei` või `ebakindel`.
API-vea kontrollimiseks kasuta vale API-aadressi või peata testteenus.

## Kontrollnimekiri

- [ ] TextEditi tavalisel tekstiväljal kuvatakse valitud teksti tulemus `jah`,
      `ei` või `ebakindel`.
- [ ] Tühja valiku korral API-päringut ei saadeta.
- [ ] Safari tavalisel teksti-, otsingu- ja `textarea`-väljal kontroll töötab.
- [ ] Chrome'i tavalisel teksti-, otsingu- ja `textarea`-väljal kontroll töötab.
- [ ] Parooli-, kirjutuskaitstud ja keelatud väli ning `contenteditable`-ala ei
      saada API-päringut.
- [ ] Menüüriba toiming ja seadistatud kiirklahv annavad sama tulemuse.
- [ ] Accessibility-loa eemaldamisel kuvatakse, et luba puudub; loa taastamisel
      hakkab kontroll pärast rakenduse uuesti avamist tööle.
- [ ] Vale või kättesaamatu API korral kuvatakse arusaadav viga ning
      **Proovi uuesti** töötab.
- [ ] Hüpikakna sulgemine katkestab poolelioleva või viivitusega päringu.
- [ ] Vaikimisi kohalikku aadressi kasutades ei lahku valitud tekst Macist.
- [ ] Kui kasutatakse HTTPS-kaugteenust, kuvatakse selle origin ja küsitakse
      nõusolek. **Loobu** ei saada päringut; **Luba ja kontrolli** saadab ühe
      päringu. Seda punkti pole vaja teha, kui kaugteenust ei avaldata.
- [ ] DMG-st kausta `/Applications` paigaldatud rakendus käivitub ja kontrollib
      valitud teksti.

## Päris AppKiti Accessibility-kontroll

Soovi korral tee sügavam päris juhtelementide kontroll:

```sh
scripts/run-native-ax-harness.sh
```

Vajuta kontrollrakenduses **Käivita kontroll** ja testhostis **Valmista ette**.
Tulemus peab olema `PASS`. Tootmisrakenduse Automaatkorrektor tavareeglistik
peab `NativeTextControlHost` hosti tagasi lükkama; erand on kompileeritud ainult
testirakendusse. Test ei kasuta võrku ega salvesta valitud teksti.

Kui kõik kasutatava väljalaske jaoks asjakohased punktid läbivad, laadi loodud
DMG sama versioonisildiga GitHub Release'i.
