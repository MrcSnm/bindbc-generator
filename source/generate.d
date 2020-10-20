
//          Copyright Marcelo S. N. Mancini(Hipreme) 2020.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module generate;
import regexes;
import std.file;
import std.process:executeShell;
import std.array;
import std.string;
import std.getopt;
import std.regex : replaceAll, matchAll, regex, Regex;
import std.path:baseName, stripExtension;
import std.stdio:writeln, File;
import pluginadapter;


enum D_TO_REPLACE
{
    loneVoid = "()",    
    unsigned_int = "uint",
    unsigned_char = "ubyte",
    _string = "const (char)*", //This will be on the final as it causes problem on regexes
    head_const = "const $1",
    _callback = "$1 function($3) $2",
    _in = " in_",
    _out = " out_",
    _align = " align_",
    _ref = " ref_",
    _struct = "",
    _array = "$1* $2"
}

enum AliasCreation = "alias p$2 = $1 function";
enum GSharedCreation = "p$2 $2";
enum BindSymbolCreation = "lib.bindSymbol(cast(void**)&$2, \"$2\");";



File createDppFile(string file)
{
    File f;
    string dppFile = baseName(stripExtension(file)) ~ ".dpp";
    if(!exists(file))
    {
        writeln("File does not exists");
        return f;
    }
    if(lastIndexOf(file, ".h") == -1)
    {
        writeln("File must be a header");
        return f;
    }
    if(!exists(dppFile))
    {
        f = File(dppFile, "w");
        f.write("#include \""~file~"\"");
        writeln("File '" ~ dppFile ~ "' created");
    }
    else
    {
        f = File(dppFile);
        writeln("File '" ~ dppFile ~ "' already exists, ignoring content creation");
    }
    return f;
}

bool executeDpp(File file, string _dppArgs)
{
    string[4] tests = ["d++", "d++.exe", "dpp", "dpp.exe"];
    string selected;
    foreach(t; tests)
    {
        if(exists(t))
        {
            selected = t;
            break;
        }
    }
    if(selected == "")
    {
        writeln("Could not create types.d\nReason: d++/dpp is not on the current folder");
        return false;
    }

    string[] dppArgs = [selected, "--preprocess-only"];
    if(_dppArgs != "")
        dppArgs~= _dppArgs.split(",");
    dppArgs~=file.name;

    auto ret = executeShell(dppArgs.join(" "));
    

    //Okay
    if(ret.status == 0)
    {
        writeln("Types.d was succesfully created with "~dppArgs.join(" "));
        //Instead of renaming, just copy its content and delete it
        string noExt = stripExtension(file.name);
        string genName = noExt~".d";
        string fileContent = "module bindbc."~ noExt~".types;\n" ~readText(genName);
        mkdirRecurse("bindbc/cimgui");
        std.file.write("bindbc/"~noExt~"/types.d", fileContent);
    }
    else
    {
        writeln(r"
Could not execute dpp:
DPP output
--------------------------------------------------
");
    writeln(ret.output);
    writeln(r"
--------------------------------------------------
End of Dpp output
");
    }
    return true;
}

/**
*   Get every function from file following the regex, the regex should only match
*/
auto getFuncs(Input, Reg)(Input file, Reg reg)
{
    if(lastIndexOf(file, ".h") == -1)
        return "";

    writeln("Getting file '"~file~"' functions");
    string f = readText(file);
    auto matches = matchAll(f, reg);
    string ret;
    foreach(m; matches)
    {
        ret~= m.hit~"\n";
    }
    return ret;
}

/**
*   Uses a bunch of presets written in the file head, it will convert every C func
* declaration to D, arrays are transformed to pointers, as if it becomes ref, the function
* won't be able to accept casts
*/
string cppFuncsToD(string funcs)
{
    alias f = funcs;
    writeln("Converting functions to D style");
    with(D_TO_REPLACE)
    {
        f = f.replaceAll(CPP_TO_D.replaceUint, unsigned_int);
        f = f.replaceAll(CPP_TO_D.replaceUByte, unsigned_char);
        f = f.replaceAll(CPP_TO_D.replaceCallback, _callback);
        f = f.replaceAll(CPP_TO_D.replaceIn, _in);
        f = f.replaceAll(CPP_TO_D.replaceOut, _out);
        f = f.replaceAll(CPP_TO_D.replaceAlign, _align);
        f = f.replaceAll(CPP_TO_D.replaceRef, _ref);
        f = f.replaceAll(CPP_TO_D.replaceStruct, _struct);
        f = f.replaceAll(CPP_TO_D.replaceArray, _array);
        f = f.replaceAll(CPP_TO_D.removeLoneVoid, loneVoid );
    }
    return funcs;
}

auto cleanPreFuncsDeclaration(Strs, Reg)(Strs funcs, Reg reg)
{
    writeln("Cleaning pre function declaration");
    funcs = replaceAll(funcs, reg, "$1");
    return funcs;
}

string[] getFuncNames(string[] funcs)
{
    writeln("Getting function names");
    foreach(ref f; funcs)
        f = f.replaceAll(GetFuncParamsAndName2, "$2");
    return funcs;
}

string generateAliases(string[] funcs)
{
    string ret = "";
    foreach(f; funcs)
    {
        string buf = f.replaceAll(GetFuncParamsAndName2, "alias da_$2 = $1 function $3;\n\t"); 
        buf = buf.replaceAll(CPP_TO_D.replaceString, D_TO_REPLACE._string);
        buf = buf.replaceAll(CPP_TO_D.replaceHeadConst, D_TO_REPLACE.head_const);
        ret~=buf;
    }
    return ret;
}

string generateGSharedFuncs(string[] funcs)
{
    string ret = "\n__gshared\n{\t";

    size_t len = funcs.length-1;
    foreach(i, f; funcs)
    {
        if(f != "")
        {
            ret~= "da_"~f~" "~f~";\n";
            if(i + 1 != len)
                ret~="\t";
        }
    }

    ret~="}";
    return ret;
}

void createFuncsFile(string libName, ref string[] funcNames)
{
    writeln("Writing funcs.d");
    string fileContent = q{
module bindbc.$.funcs;
import bindbc.$.types;
import core.stdc.stdarg:va_list;

extern(C) @nogc nothrow
}.replaceAll(DollarToLib, libName);
    fileContent~="{\n\t";
    fileContent~=generateAliases(funcNames);
    fileContent~="\n}";

    funcNames = getFuncNames(funcNames);
    fileContent~=generateGSharedFuncs(funcNames);
    
    mkdirRecurse("bindbc/"~libName);
    std.file.write("./bindbc/"~libName~"/funcs.d", fileContent);
}

/**
*   
*/
string generateBindSymbols(string[] funcs)
{
    string ret = "";
    size_t len = funcs.length-1;
    foreach(i, f; funcs)
    {
        if(f != "")
            ret~= "lib.bindSymbol(cast(void**)&"~f~", \""~f~"\");\n";
        if(i + 1 != len)
            ret~="\t";
    }
    return ret;
}


/**
*   Create library loading file named libNameload.d
*/
void createLibLoad(string libName, string[] funcNames)
{
    writeln("Writing "~libName~"load.d");
    string fileContent = "module bindbc."~libName~"."~libName~"load;\n";
    fileContent~="import bindbc.loader;\n";
    fileContent~="import bindbc."~libName~".types;\n";
    fileContent~="import bindbc."~libName~".funcs;\n";
    fileContent~="private\n{\n\tSharedLib lib;\n}";
    fileContent~=`
bool load$()
{
    version(Windows){
        const (char)[][1] libNames = ["$.dll"];
    }
    else version(OSX){
        const(char)[][7] libNames = [
        "lib$.dylib",
        "/usr/local/lib/lib$.dylib",
        "/usr/local/lib/lib$/lib$.dylib",
        "../Frameworks/$.framework/$",
        "/Library/Frameworks/$.framework/$",
        "/System/Library/Frameworks/$.framework/$",
        "/opt/local/lib/lib$.dylib"
        ];
    }
    else version(Posix){
        const(char)[][8] libNames = [
        "$.so",
        "/usr/local/lib/$.so",
        "$.so.1",
        "/usr/local/lib/$.so.1",
        "lib$.so",
        "/usr/local/lib/lib$.so",
        "lib$.so.1",
        "/usr/local/lib/lib$.so.1"
        ];  
    }
    else static assert(0, "bindbc-$ is not yet supported on this platform.");
    foreach(name; libNames) 
    {
        lib = load(name.ptr);
        if(lib != invalidHandle)
            return _load();
    }
    return false;
}`;
// };//Token strings for some reason seems to be jumping more lines than the expected
    fileContent~=r"
private bool _load()
{
    bool isOkay = true;
    import std.stdio:writeln;
    const size_t errs = errorCount();
    loadSymbols();
    if(errs != errorCount())
    {
        isOkay = false;
        import std.conv:to;
        foreach(err; errors)
        {
            writeln(to!string(err.message));
        }
    }
    return isOkay;
}";
// };
    fileContent = replaceAll(fileContent, DollarToLib, libName);
    fileContent~="private void loadSymbols()\n{\n\t";
    fileContent~= generateBindSymbols(funcNames);
    fileContent~="}";

    File _f = File("bindbc/"~libName~"/"~libName~"load.d", "w");
    _f.write(fileContent);
    _f.close();
}

void createPackage(string libName)
{
    //No need to regenerate it everytime
    if(exists("bindbc/"~libName~"/package.d"))
        return;
    string fileContent = q{
module bindbc.$;

public import bindbc.$.funcs;
public import bindbc.$.$load;
public import bindbc.$.types;
}.replaceAll(DollarToLib, libName);
    std.file.write("bindbc/"~libName~"/package.d", fileContent);
}



enum ERROR = -1;

string optFile;
string optDppArgs;
string optPresets;
bool optNoTypes;
string optCustom;
bool optFuncPrefix;

int main(string[] args)
{
    GetoptResult helpInfo;
    try
    {
        helpInfo = getopt(
            args,
            "dpparg|d", &optDppArgs,
            "file|f", &optFile,
            "presets|p", &optPresets,
            "notypes|n", &optNoTypes,
            "custom|c", &optCustom,
            "use-func-prefix|u", &optFuncPrefix
        );
    }
    catch(Exception e)
    {
        writeln(e.msg);
        return ERROR;
    }
    //I don't really understand what type is regex...
    Regex!char targetReg;

    //Dpparg
    helpInfo.options[0].help = "Arguments to be appended to dpp, --preprocess-only is always included. Pass multiple arguments via comma";
    //File
    helpInfo.options[1].help = "Target header to get functions and types for generation";
    //Presets
    helpInfo.options[2].help = r"
(Presets and custom are mutually exclusive)
Function getter presets:
   cimgui - Preset used for compiling libcimgui -> https://github.com/cimgui/cimgui
";
    helpInfo.options[3].help = "Don't execute Dpp, and don't generate the types file";
    //Custom
    helpInfo.options[4].help =r"
Flags m and g are always added, $1 must always match function without exports.
Examples: 
    void func(char* str);
    int main();
";
    //Prefix-only
    helpInfo.options[5].help = r"
This will be the prefix of your regex.
The postfix will be a predefined one for function format:
    Appends ^(?: at the start(The one which is meant to be ignored)
    Appends )(.+\);)$ at the end (Finish the ignored one and append the function $1 one)
";
    if(optPresets != "")
    {
        switch(optPresets)
        {
            case "cimgui":
                targetReg = Presets.cimguiFuncs;
                optDppArgs = "--parse-as-cpp,--define CIMGUI_DEFINE_ENUMS_AND_STRUCTS";
                if(optFile == "")
                    optFile = "cimgui.h";
                break;
            default:
                writeln("Preset named '"~optPresets~"' does not exists");
                break;
        }
    }

    if(optPresets == "" && optCustom != "")
    {
        writeln("
Please consider adding your custom function getter to the list.
Just create an issue or a pull request on https://www.github.com/MrcSnm/bindbc-generator
");
        string reg;
        if(optFuncPrefix)
        {
            reg~=r"^(?:";
            reg~=optCustom;
            reg~=r")(.+\);)$";
        }
        else
            reg~= optCustom;
        writeln("Compiling regex");
        targetReg = regex(reg, "mg"); //Auto converts single slash to double for easier usage
        writeln("Regex Generated:\n\t"~targetReg.toString);
    }

    if(helpInfo.helpWanted || (optFile == ""))
    {
        if(optFile == "")
            writeln("File options is missing, you should always specify the target!");
        defaultGetoptPrinter(r"
Bindbc-generator options.
If you find an issue with the content generation, report it at
https://www.github.com/MrcSnm/bindbc-generator
",
        helpInfo.options);
        return 1;
    }
    string _f = optFile;
    if(!optNoTypes)
    {
        if(optDppArgs == "")
        {
            writeln(r"
No dpp arg specified!
Beware that for this project it is used for generating struct and enums ONLY
Functions definitions comes from the .h file specified
");
        }
        File f = createDppFile(_f);
        if(f.name == "")
            return ERROR;
        executeDpp(f, optDppArgs);
    }
    if(optPresets == "" && optCustom == "")
    {
        writeln("ERROR:\nNo regex nor presets for getting functions specified\n");
        return ERROR;
    }
    string funcs = getFuncs(_f, targetReg);
    if(funcs == "")
    {
        writeln("ERROR:\nNo hit was made by your function");
        return ERROR;
    }
    string cleanFuncs = cleanPreFuncsDeclaration(funcs, targetReg);
    string dfuncs = cppFuncsToD(cleanFuncs);
    string[] darrFuncs = dfuncs.split("\n");

    //It will already remove darrFuncs params
    string libName = stripExtension(_f);
    createFuncsFile(libName, darrFuncs);     
    createLibLoad(libName, darrFuncs);    
    createPackage(libName);

    if(!optNoTypes)
        remove(_f.stripExtension ~ ".d");
    return 1;
} 