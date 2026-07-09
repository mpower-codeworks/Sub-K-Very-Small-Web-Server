# Sub-K -- a very small web server

<img src="images/logo2.png" align="left" width="100" alt="Sub-K Logo">

Sub-K is a Win32 static web server in 932 bytes. Features include requested file serving, index.htm default routing, basic MIME type support, and thread-per-client concurrent connections. Default port is 8080.

Sub-K follows in the same tradition as [DTE](https://github.com/mpower-codeworks/Daves-Tiny-Editor), [HelloAssembly](https://github.com/PlummersSoftwareLLC/HelloAssembly), and [TRPad](https://github.com/mpower-codeworks/TinyRetroPad). It's not really descended from any of those, aside from the flat memory model. My inspiration for Sub-1KB works came directly from Dave Plummer's HelloAssembly which again, can be found [here](https://github.com/PlummersSoftwareLLC/HelloAssembly). 

Sub-K compiles with MASM and Crinkler. The build for this presentation is set at 932 bytes exe using 11.7 MB of RAM at run time. These are configurable. The source code history also offers "stages". If, for example, you want a much smaller exe with less features, you can build version sbk_017 for a single connection, single html page server in 657 bytes.

If that isn't small enough for you, try version sbk_014 which has hard-coded "hello" and comes in at 552 bytes. The exe size will grow/shrink byte-for-byte as you put in your custom text.

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
