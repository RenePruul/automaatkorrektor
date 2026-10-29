# Windowsi valitud teksti prototüüp

> PROTOTÜÜP. See pole tootmiskood ega kuulu `main` harusse.

Prototüüp kontrollib, kas Windows UI Automation võimaldab Windows 10 build
19045 Notepadist lugeda ainult üht valitud tekstivahemikku ilma lõikelauda või
kogu dokumenti lugemata. Valitud teksti ei väljastata ega saadeta võrku.

## Käivitamine

Vajalik on Windows x64 ja .NET 8 SDK.

```powershell
dotnet run --configuration Release
```

Kui programm alustab viiesekundilist loendust:

1. ava tavaliste õigustega Notepad;
2. kirjuta `KANAARILIND-123`;
3. vali täpselt see tekst;
4. hoia Notepad fookuses kuni tulemuseni.

Edukas põhikatse kuvab:

```text
PASS: täpne kanaarilinnu valik loeti ilma seda väljastamata.
```

## Katsed

Käivita programm iga katse jaoks uuesti ja märgi tulemus.

| Katse | Oodatud tulemus |
|---|---|
| Tavaline Notepad, valitud `KANAARILIND-123` | `PASS: täpne kanaarilinnu valik...` |
| Tavaline Notepad, ainult kursor | `PASS: tühi valik lükati tagasi.` |
| Muu fookuses rakendus | `PASS: muu rakendus lükati tagasi.` |
| Administraatorina käivitatud Notepad | `PASS: kõrgendatud Notepad lükati tagasi.` või ligipääsu tagasilükkamine |
| Üle 10 000 märgi valik | `PASS: liiga pikk valik lükati tagasi.` |

Liiga pika valiku testfaili saab luua PowerShellis:

```powershell
[IO.File]::WriteAllText("$env:TEMP\automaatkorrektor-pikk.txt", "a" * 10001)
notepad "$env:TEMP\automaatkorrektor-pikk.txt"
```

Vali Notepadist kogu tekst ja käivita prototüüp teises terminalis.

## Mida raporteerida

- Windowsi täielik versioon ja build;
- iga katse `PASS` või `FAIL` rida;
- kuvatud aeg millisekundites;
- kas protsess jäi kinni või sulgus ise.

Ära lisa raportisse valitud teksti ega muid isikuandmeid.
