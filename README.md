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

## Options
```
-d  --dpparg Arguments to be appended to dpp, --preprocess-only is always included. Pass multiple arguments via comma
-f    --file Target header to get functions and types for generation
-p --presets
(Presets and custom are mutually exclusive)
Function getter presets:
   cimgui - Preset used for compiling libcimgui -> https://github.com/cimgui/cimgui

-n --notypes Don't execute Dpp, and don't generate the types file
-c  --custom
Flags m and g are always added, $1 must always match function without exports.
Examples:
    void func(char* str);
    int main();
-u  --use-func-prefix
This will be the prefix of your regex.
The postfix will be a predefined one for function format:
    Appends ^(?: at the start(The one which is meant to be ignored)
    Appends )(.+\);)$ at the end (Finish the ignored one and append the function $1 one)

-h    --help This help information.
```