module generate;
import regexes;
import std.file;
import std.process:execute;
import std.array;
import std.string;
import std.regex : replaceAll, matchAll;
import std.path:baseName, stripExtension;
import std.stdio:writeln, File;


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

enum AliasCreation = "alias da_$2 = $1 function";
enum GSharedCreation = "da_$2 $2";
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
        writeln(f.name);
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
            writeln(selected~" found, creating types.d");
            break;
        }
    }
    if(selected == "")
    {
        writeln("Could not create types.d\nReason: d++/dpp is not on the current folder");
        return false;
    }

    string dppArgs = selected~" --parse-as-cpp --preprocess-only " ~_dppArgs ~ " "~ file.name;

    execute(dppArgs.split(" "));
    
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
    // ret.reserve(1024);
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
    size_t len = funcs.length;
    foreach(i, f; funcs)
    {
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



enum ERROR = -1;
int main(string[] args)
{
    string _f = args[1];
    File f = createDppFile(_f);
    if(f.name == "")
        return ERROR;
    executeDpp(f, "");
    string funcs = getFuncs(_f, Presets.cimguiFuncs);
    string cleanFuncs = cleanPreFuncsDeclaration(funcs, Presets.cimguiFuncs);
    string dfuncs = cppFuncsToD(cleanFuncs);
    string[] darrFuncs = dfuncs.split("\n");

    //It will already remove darrFuncs params
    createFuncsFile(stripExtension(_f), darrFuncs);     
    createLibLoad(stripExtension(_f), darrFuncs);
    
    

    return 1;
} 