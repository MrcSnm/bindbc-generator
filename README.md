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