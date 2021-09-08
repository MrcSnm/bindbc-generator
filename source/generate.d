
//          Copyright Marcelo S. N. Mancini(Hipreme) 2020.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module generate;
import regexes;
import std.file;
import std.process : executeShell;
import std.array;
import std.string;
import std.getopt;
import std.regex : replaceAll, matchAll, regex, Regex;
import std.path;
import std.stdio : writeln, File;
import pluginadapter;
import plugin;


string dppPath;
string pluginsPath;
string tempPath;
string optFile;
string optDppArgs;
string optPresets;
bool optNoTypes;
bool optLoad;
string optCustom;
bool optFuncPrefix;
string[] optUsingPlugins = [];
bool optLoadAll;
string[][string] optPluginArgs;
bool optRecompile;
bool optDebug;

void helpInfoSetup(ref GetoptResult helpInfo)
{
    size_t i = 0;
    // Dpp path
    helpInfo.options[i++].help = "Path to dpp executable. Searched for in PATH if not specified.";
    // Plugins path
    helpInfo.options[i++].help = "Path to plugins folder. Default is `plugins`.";
    // 
    helpInfo.options[i++].help = "Path to temporary directory. Default is `temp`.";
    //Dpparg
    helpInfo.options[i++].help = "Arguments to be passed to dpp, --preprocess-only is always included. Pass multiple arguments via comma";
    //File
    helpInfo.options[i++].help = "Target header to get functions and types for generation";
    //Presets
    helpInfo.options[i++].help = r"
(Presets and custom are mutually exclusive)
Function getter presets:
   cimgui - Preset used for compiling libcimgui -> https://github.com/cimgui/cimgui
";
    helpInfo.options[i++].help = "Don't execute Dpp, and don't generate the types file";
    //Custom
    helpInfo.options[i++].help =r"
Flags m and g are always added, $1 must always match function without exports.
Examples: 
    void func(char* str);
    int main();
";
    //Prefix-only
    helpInfo.options[i++].help = r"
This will be the prefix of your regex.
The postfix will be a predefined one for function format:
    Appends ^(?: at the start(The one which is meant to be ignored)
    Appends )(.+\);)$ at the end (Finish the ignored one and append the function $1 one)
";
    //Plugin-load
    helpInfo.options[i++].help = r"
Loads plugins located in the plugins folder. For the plugin being loaded it must:
    1: Export a function named export(Modulename) which returns a Plugin instance.
    2: Have a compiled .dll or .so following the scheme 'libpluginPLUGIN_FOLDER_NAME'
        2.1: If you need many exports in a single dll, create a package.d with public imports and
        compile it, plugin finding is first folder only, i.e: not recursive.
";
    //Load all
    helpInfo.options[i++].help = r"
Loads every plugin located in the plugins folder";
    //Plugins args
    helpInfo.options[i++].help = r"
Arguments to pass to a plugin's entry point.
Only the plugins with at least args 1 arg will be executed, pass a null string if you wish
to pass only the current working dir.

Example on multiple args -> --plugin-args myplugin=[arg1 arg2 arg3]

Reserved arguments are:
    d-conv -> Converts from C to D; every plugin that receives that argument will have its string from convertToD_Pipe() converted to D style
";
    //Recompile
    helpInfo.options[i++].help = r"
Using this option will force a recompilation of the plugins!";
    //Debug
    helpInfo.options[i++].help = r"
Compile dynamic libraries with debug symbols enabled";
}

int main(string[] args)
{
    GetoptResult helpInfo;
    try
    {
        helpInfo = getopt(
            args,
            "dpp-path", &dppPath,
            "plugins-path", &pluginsPath,
            "temp-path", &tempPath,
            "dpparg|d", &optDppArgs,
            "file|f", &optFile,
            "presets|p", &optPresets,
            "notypes|n", &optNoTypes,
            "custom|c", &optCustom,
            "use-func-prefix|u", &optFuncPrefix,
            "load-plugins|l", &optUsingPlugins,
            "load-all", &optLoadAll,
            "plugin-args|a", &pluginArgsHandler,
            "recompile|r", &optRecompile,
            "debug", &optDebug
        );
    }
    catch(Exception e)
    {
        writeln(e.msg);
        return Plugin.ERROR;
    }
    if (pluginsPath is null) 
        pluginsPath = "plugins";
    if (tempPath is null)
        tempPath = "temp";
    if (!exists(tempPath))
        mkdirRecurse(tempPath);
    if (optFile !is null)
        optFile = absolutePath(optFile);
    helpInfoSetup(helpInfo);
    //I don't really understand what type is regex...
    Regex!char targetRegex;

    if(!checkPluginLoad())
        return Plugin.ERROR;
    getDConvPlugins();

    bool pluginOnly = checkPluginOnly();

    if(!pluginOnly)
    {
        checkPresets(targetRegex);
        checkCustomRegex(targetRegex);
    }

    if(checkHelpNeeded(helpInfo))
        return 1;
    
    if(!pluginOnly)
    {
        if(!checkDppExecution())
            return Plugin.ERROR;
        if(optPresets == "" && optCustom == "")
        {
            writeln("ERROR:\nNo regexes or presets for getting functions specified\n");
            return Plugin.ERROR;
        }
        string funcs = getFuncs(optFile, targetRegex);
        if(funcs == "")
        {
            writeln("ERROR:\nNo hit was made by your function");
            return Plugin.ERROR;
        }
        string cleanFuncs = cleanPreFuncsDeclaration(funcs, targetRegex);
        string dfuncs = cppFuncsToD(cleanFuncs);
        string[] darrFuncs = dfuncs.split("\n");

        //It will already remove darrFuncs params
        string libName = baseName(stripExtension(optFile));
        createFuncsFile(libName, darrFuncs);
        createLibLoad(libName, darrFuncs);    
        createPackage(libName);

        if(!optNoTypes)
            remove(buildPath(tempPath, optFile.setExtension(".d").baseName));
    }
    playPlugins(args[0]);
    
    return Plugin.SUCCESS;
} 


File createDppFile(string headerFile)
{
    File f;
    if(!exists(headerFile))
    {
        writeln("File does not exists");
        return f;
    }
    if(lastIndexOf(headerFile, ".h") == -1)
    {
        writeln("File must be a header");
        return f;
    }

    string dppFilePath = buildPath(tempPath, headerFile.setExtension("dpp").baseName());
    if(exists(dppFilePath))
    {
        f = File(dppFilePath);
        writeln("File '" ~ dppFilePath ~ "' already exists, ignoring content creation");
        return f;
    }
    
    f = File(dppFilePath, "w");
    f.write("#include \""~absolutePath(headerFile)~"\"");
    writeln("File '" ~ dppFilePath ~ "' created");
    return f;
}

// Gets the generated dpp file and generates a d file
bool executeDpp(File file, string _dppArgs)
{
    string dppExecutableName;

    if(dppPath !is null)
    {
        if(exists(dppPath))
            dppExecutableName = dppPath;
        else
        {
            writeln("Could not create types.d\nReason: dpp not found by the specified path");
            return false;
        }
    }
    else
    {
        string[4] tests = ["d++", "d++.exe", "dpp", "dpp.exe"];
        foreach(t; tests)
        {
            if(exists(t))
            {
                dppExecutableName = t;
                break;
            }
        }
        if(dppExecutableName == "")
        {
            writeln("Could not create types.d\nReason: d++ (or dpp) is not in the current folder");
            return false;
        }
    }

    string[] dppArgs = [dppExecutableName, "--preprocess-only"];
    if(_dppArgs != "")
        dppArgs ~= _dppArgs.split(",");

    // `file.name` is the header file
    dppArgs ~= file.name;
    dppArgs ~= "--source-output-path";
    dppArgs ~= tempPath;

    auto ret = executeShell(dppArgs.join(" "));
    
    //Okay
    if(ret.status == 0)
    {
        const generatedModuleName = file.name.stripExtension().baseName();
        const generatedFilePath = file.name.setExtension("d");

        writeln("Types.d was succesfully created with "~dppArgs.join(" "));
        //Instead of renaming, just copy its content and delete it
        string fileContent = "module bindbc." ~ generatedModuleName ~ ".types;\n" ~ readText(generatedFilePath);
        mkdirRecurse("bindbc/"~generatedModuleName);
        std.file.write("bindbc/"~generatedModuleName~"/types.d", fileContent);
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
    _sizeof = "$1.sizeof",
    //C++ part
    _template = "$2!($1)",

    addressDefault = "$1 $2 = $3", //Ignores ref for the first def
    addressAllRef = "ref $1 $2", //Ignores ref for the first def
    address = "ref $1",
    NULL = " null",
    CONST = "const ($1)",

    _struct = "",
    _array = "$1* $2",
    _nullAddress = " null"
}

enum AliasCreation = "alias p$2 = $1 function";
enum GSharedCreation = "p$2 $2";
enum BindSymbolCreation = "lib.bindSymbol(cast(void**)&$2, \"$2\");";


/**
*   Uses a bunch of presets written in the file head, it will convert every C func
* declaration to D, arrays are transformed to pointers, as if it becomes ref, the function
* won't be able to accept casts
*/
string cppFuncsToD(string funcs, bool replaceAditional = false)
{
    alias f = funcs;
    writeln("Converting functions to D style");
    with(D_TO_REPLACE)
    {
        f = f.replaceAll(CPP_TO_D.replaceRef, _ref);
        replaceRefWithDefault(funcs);
        f = f.replaceAll(CPP_TO_D.replaceUint, unsigned_int);
        f = f.replaceAll(CPP_TO_D.replaceUByte, unsigned_char);
        f = f.replaceAll(CPP_TO_D.replaceCallback, _callback);
        f = f.replaceAll(CPP_TO_D.replaceIn, _in);
        f = f.replaceAll(CPP_TO_D.replaceOut, _out);
        f = f.replaceAll(CPP_TO_D.replaceAlign, _align);

        f = f.replaceAll(CPP_TO_D.replaceSizeof, _sizeof);
        //C++ Part
        f = f.replaceAll(CPP_TO_D.replaceTemplate, _template);
        f = f.replaceAll(CPP_TO_D.replaceAddress, address);
        f = f.replaceAll(CPP_TO_D.replaceNULL, NULL);
        f = f.replaceAll(CPP_TO_D.replaceCONST, CONST);

        f = f.replaceAll(CPP_TO_D.replaceStruct, _struct);
        f = f.replaceAll(CPP_TO_D.replaceArray, _array);
        f = f.replaceAll(CPP_TO_D.replaceNullAddress, _nullAddress);
        f = f.replaceAll(CPP_TO_D.removeLoneVoid, loneVoid );
        
        if(replaceAditional)
        {
            f = f.replaceAll(CPP_TO_D.replaceString, _string);
            f = f.replaceAll(CPP_TO_D.replaceHeadConst, head_const);
        }
    }
    return funcs;
}

import std.regex:Captures, RegexMatch;
string[] capturesToArray(RegexMatch!string matches)
{
    string[] ret;
    foreach(m; matches.array)
        ret~= m.hit;
    return ret;
}

/**
*   Creates overload for ref functions with defaults
*/
void replaceRefWithDefault(ref string funcs)
{
    foreach(ref line; funcs.splitLines)
    {
        auto matches = line.matchAll(CPP_TO_D.replaceAddressDefault);
        if(matches)
        {   
            //Generate ref and non ref default
            string toAppend = line.replaceAll(CPP_TO_D.replaceAddressDefault, D_TO_REPLACE.addressDefault);
            import std.regex : matchFirst;
            if(!line.matchFirst(CPP_TO_D.hasDefaultArg))
                toAppend~= "\n" ~line.replaceAll(CPP_TO_D.replaceAddressDefault, D_TO_REPLACE.addressAllRef);
            funcs = funcs.replaceFirst(line, toAppend);
        }
    }
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



enum ReservedArgs : string
{
    D_CONV = "d-conv"
}
/**
*   Remove d-conv from the args and sets willConvertToD to true
*/
void getDConvPlugins()
{
    import std.algorithm : countUntil;
    foreach(pluginName, args; optPluginArgs)
    {
        long ind = countUntil(args, ReservedArgs.D_CONV);
        if(ind != -1)
        {
            if(ind != args.length)
                optPluginArgs[pluginName] = args[0..ind] ~ args[ind+1..$];
            else
                optPluginArgs[pluginName] = args[0..ind];
            PluginAdapter.loadedPlugins[pluginName].willConvertToD = true;
        }
    }
}

void pluginArgsHandler(string opt, string value)
{
    import std.array:split;
    import std.algorithm:countUntil;
    if(opt == "plugin-args|a")
    {
        if(value.countUntil("=") == -1)
            return writeln("plugin-args wrong formatting! It must be --plugin-args pluginname=\"[arg1 arg2]\" or -a pluginname=\"[arg1 arg2]\"");
        string[] v = value.split("=");
        string pluginName = v[0];
        if(v[1][0] == '[')
        {
            if(v[1][$-1] != ']')
            {
                writeln("Plugin argument error! If the plugins argument list starts with '[', it MUST end with ']'. Argument sent: ", value);
                return;
            }
            else
                optPluginArgs[pluginName]~= v[1][1..$-1].split(" ");
        }
        else
            optPluginArgs[pluginName]~= v[1];
    }
}

void playPlugins(string cwd)
{
    foreach(pluginName, pluginArgs; optPluginArgs)
    {
        Plugin* p = (pluginName in PluginAdapter.loadedPlugins);
        if(p is null)
        {
            writeln("Plugin named '"~pluginName~"' does not exists!\nAvailable plugins list:");
            foreach(k, v; PluginAdapter.loadedPlugins)
                writeln("- ", k);
            return;
        }
        writeln("'", pluginName, "' under execution with arguments ", cwd~pluginArgs, "\n\n\n");
        int retVal = p.main(cwd ~ pluginArgs);
        if(retVal == Plugin.SUCCESS)
        {
            string processed = p.convertToD_Pipe();
            if(p.willConvertToD)
                processed = cppFuncsToD(processed, true);
            if(p.onReturnControl(processed) == Plugin.ERROR)
                goto PLUGIN_ERROR;
            writeln("'", pluginName, "' finished tasks.\n\n\n");
            p.hasFinishedExecution = true;
        }
        else
        {
            PLUGIN_ERROR: writeln("Error ocurred while executing '", pluginName, "'!\n\t->", p.error);
        }
    }
}

void checkPresets(ref Regex!char targetReg)
{
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
}

void checkCustomRegex(ref Regex!char targetReg)
{
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
}


bool checkHelpNeeded(ref GetoptResult helpInfo)
{
    if(helpInfo.helpWanted || (optFile == "" && optUsingPlugins.length == 0))
    {
        if(optFile == "" && optUsingPlugins.length == 0)
            writeln("File options is missing, you should always specify the target or specify a plugin!");
        
        defaultGetoptPrinter(r"
Bindbc-generator options.
If you find an issue with the content generation, report it at
https://www.github.com/MrcSnm/bindbc-generator
",
        helpInfo.options);
        return true;
    }
    return false;
}

bool checkPluginLoad()
{
    if(optUsingPlugins.length != 0 || optLoadAll)
    {
        if(optLoadAll)
            optUsingPlugins = PluginAdapter.loadPlugins(pluginsPath, optUsingPlugins, optRecompile, optDebug);
        else
            PluginAdapter.loadPlugins(pluginsPath, optUsingPlugins, optRecompile, optDebug);
        int nullCount = 0;
        if(optUsingPlugins.length == 0)
        {
            writeln("\n\nERROR!\nCould not load any plugin!");
            return false;
        }
        foreach(p; optPluginArgs)
        {
            if(p.length == 0)
                nullCount++;
        }
        if(nullCount == optPluginArgs.length)
        {
            writeln(r"
Plugins loaded but none was specified for execution!
For executing it, you must at least specify one plugin arg.
Showing loaded plugins help info:");
            foreach(k, v; PluginAdapter.loadedPlugins)
            {
                if(v.getHelpInformation() == "")
                    writeln("\n\nWARNING!\n\nContact ", k, " provider! No help information is given");
                else
                    writeln("\n\n", k, "\n\n",
r"--------------------------------",
v.getHelpInformation());
            }
            return false;
        }
    }
    return true;
}

bool checkDppExecution()
{
    string _f = optFile;
    if(!optNoTypes)
    {
        if(optDppArgs == "")
        {
            writeln(r"
No dpp arg specified!
Beware that for this project uses dpp for generating struct and enums ONLY
Functions definitions comes from the .h file specified and then replaces with
D style
");
        }
        File f = createDppFile(_f);
        if(f.name == "")
            return false;
        return executeDpp(f, optDppArgs);
    }
    return true;
}

bool checkPluginOnly()
{
    return (optFile == "" && optPresets == "" && optCustom == "" && optDppArgs == "" &&
    (optUsingPlugins.length != 0 || optLoadAll));
}

