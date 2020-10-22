# Bindbc-Generate

The purpose of this repository is to auto generate C bindings based on the
bindbc pattern, it has dependencies on:

- Compiling -> [Dlang + Dub](https://dlang.org/download.html)
- [D++(Dpp)](https://github.com/atilaneves/dpp)
- [Clang(libclang)](https://releases.llvm.org/download.html)
>> This is a dependency of Dpp. Dpp is used to automatically generate the structs and enum
definitions, so it is extremely important to that. If you don't want to bother in generating
the structs and enums, you can execute safely this program, it will generate automatically
the functions aliases and bind symbols.
- [bindbc-loader](https://github.com/BindBC/bindbc-loader)
>> This one is actually a dependency of the output project

PR's are welcome, every project created using bindbc-generator, please, link to this repo.
If you find any issue when generating the functions, just create an issue on this repository


# What's New

BindBC Generator now supports plugin coding.
The plugins are made for being able to execute some main part of the program without relying any dependency.
Although right now, it exports the symbol based on the source name, so it still requires the source
to be on the plugin folder, right now, the design could support something like that, but it would
require that every plugin define some function that would need to mention what every exported function
name is.
So, for me, right now, it is quite complete and easy to use, it already compiles the dll on the plugins
folders.

For writing a plugin you must:

myplugin.d
```d
import plugin;


class MyPlugin : Plugin
{
    override string target(){return "myplugin-behavior";}
    override int main(string[] args) //Should return Plugin.SUCCESS or Plugin.ERROR
    override string getHelpInformation() //Provide a useful information here
    override string convertToD_Pipe() //This function you must return the string to be processed on bindbc-generator, right now only cppFuncToD is available
    override int onReturnControl(string processedString) //This is the last execution point on your plugin, it receives on the parameter the processed string from bind generator

    final int returnError(string error) //This is a snippet function for returning from main passing a message to the main program
}

Plugin exportMyplugin(){return new MyPlugin();}
```

Now, when executing the program, you will need to pass some argument like:
```

```

## Options
```
Bindbc-generator options.
If you find an issue with the content generation, report it at
https://www.github.com/MrcSnm/bindbc-generator

-d          --dpparg Arguments to be appended to dpp, --preprocess-only is always included. Pass multiple arguments via comma  
-f            --file Target header to get functions and types for generation
-p         --presets
(Presets and custom are mutually exclusive)
Function getter presets:
   cimgui - Preset used for compiling libcimgui -> https://github.com/cimgui/cimgui

-n         --notypes Don't execute Dpp, and don't generate the types file
-c          --custom
Flags m and g are always added, $1 must always match function without exports.
Examples:
    void func(char* str);
    int main();

-u --use-func-prefix
This will be the prefix of your regex.
The postfix will be a predefined one for function format:
    Appends ^(?: at the start(The one which is meant to be ignored)
    Appends )(.+\);)$ at the end (Finish the ignored one and append the function $1 one)

-l    --load-plugins
Loads plugins located at the plugins folder. For the plugin being loaded it must:
    1: Export a function named export(Modulename) which returns a Plugin instance.
    2: Have a compiled .dll or .so following the scheme 'libpluginPLUGIN_FOLDER_NAME'
        2.1: If you need many exports in a single dll, create a package.d with public imports and
        compile it, plugin finding is first folder only, i.e: not recursive.

          --load-all
Loads every plugin located at the plugis folder
-a     --plugin-args
Plugins arguments to pass into the entrance point.
Only the plugins with at least args 1 arg will be executed, pass a null string if you wish
to pass only the current working dir.

Example on multiple args-> -a myplugin=[arg1 arg2 arg3]

Reserved arguments are:
    d-conv -> Converts from C to D

-r       --recompile
Using this option will force a recompilation of the plugins!
             --debug
Compile dynamic libraries with debug symbols enabled
-h            --help This help information.
```