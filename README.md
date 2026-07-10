# Sub-K - a very small web server in 932 bytes

<img src="images/logo2.png" align="left" width="100" alt="Sub-K Logo">

Sub-K is a Win32 static web server in 932 bytes. Features include requested file serving, index.htm default routing, basic MIME type support, and thread-per-client concurrent connections. Default port is 8080.

Sub-K follows in the same tradition as [DTE](https://github.com/mpower-codeworks/Daves-Tiny-Editor), [HelloAssembly](https://github.com/PlummersSoftwareLLC/HelloAssembly), and [TRPad](https://github.com/mpower-codeworks/TinyRetroPad). It's not really descended from any of those, aside from the flat memory model. My inspiration for Sub-1KB works came directly from Dave Plummer's HelloAssembly which again, can be found [here](https://github.com/PlummersSoftwareLLC/HelloAssembly). 

Sub-K compiles with MASM and Crinkler. The build for this presentation is set at 932 bytes exe using 11.7 MB of RAM at run time. These are configurable. The source code history also offers "stages". If, for example, you want a much smaller exe with less features, you can build version sbk_017 for a single connection, single html page server in 657 bytes.

If that isn't small enough for you, try version sbk_014 which has hard-coded "hello" and comes in at 552 bytes. The exe size will grow/shrink byte-for-byte as you put in your custom text.

<table>
    <tr>
        <td align="left" width="44%" valign="top">
            <img src="images/svr_window.png" width="100%" alt="title_screen"><br>
            The server running. There was no room left for messages.
        </td>
        <td align="left" width="50%" valign="top">
            <img src="images/index.png" width="100%" alt="royal_bed"><br>
            The Sub-K default start page
        </td>
    </tr>
</table>

## What is the point of this?

I just wanted to. It's fun.

## Is this production ready?

No. Sub-K is a sizecoding experiment and tiny local/static web server. It is not meant to replace a hardened production server.

## You said exe size and RAM usage are configurable?

Yes. In build.bat change the value of HASHSIZE: to a lower number for a larger exe and lower RAM usage. For example, on the 932 byte version setting HASHSIZE:1 raises the exe size to 946 bytes and lowers RAM usage to 1.7 MB. Testing reveals that HASHSIZE:11 is about the limit. Any higher offers little or no byte savings and RAM usage can start getting bonkers.

## Do I have to use Crinkler?

Not at all. I've included build_no_crinkler.bat for compiling using only MASM. This makes the former 932 byte version 5.5 KB and reduces RAM usage to 0.5 MB, and also helps with A/V woes. I personally use Crinkler because I have interest in making usable Windows programs under 1 KB, that's all.

## Couldn't you come up with a better name?
"Hoagie" "Italian" and "#10" were considered. Actually "hoagie" for a server name makes me laugh. I may go back to that one in the future.

## Compiling Sub-K

**Important:** Programs using Crinkler can be flagged as a false positive by antivirus, including Windows Defender. You may need to make an antivirus exception folder to build this, or Windows may delete the EXE as soon as the build completes. Therefore, try this out AT YOUR OWN RISK - NO WARRANTIES / NO GUARANTEES. You can accomplish this with PowerShell.

- MASM version used: Microsoft (R) Macro Assembler Version 14.44.35224.0 <br>

- MASM can vary depending on version. If you experience:
```
C:\masm32\include\winextra.inc(11052) : error A2026:constant expected
C:\masm32\include\winextra.inc(11053) : error A2026:constant expected
```
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;In masm32\include\winextra.inc change:<br>
```
    STD_ALERT struct<br>
        alrt_timestamp dd ?<br>
        alrt_eventname WCHAR  [EVLEN + 1] dup(?)
        alrt_servicename WCHAR [SNLEN + 1] dup(?)
    STD_ALERT ends
```
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;to:<br>
```
    STD_ALERT struct<br>
        alrt_timestamp dd ?<br>
        alrt_eventname WCHAR  (EVLEN + 1) dup(?)
        alrt_servicename WCHAR (SNLEN + 1) dup(?)
    STD_ALERT ends<br>
```
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;The brackets on lines 13,14 were changed to parens.<br>
- Build.bat contains: /LIBPATH:"C:\Program Files (x86)\\Windows Kits\\10\\Lib\\10.0.20348.0\\um\\x86"<br>
You may need to change to fit your system: /LIBPATH:"....\\Windows Kits\\10\\Lib\\(your version)\\um\\x86"
- You need to have Crinkler installed in a directory that has been added to PATH.<br>
Example: C:\utils\Crinkler.exe<br>
