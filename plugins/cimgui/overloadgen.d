module overloadgen;
import plugin;
import std.stdio;
import std.json;
import std.array : split;
import std.algorithm : countUntil;
import std.file : readText, exists;

bool willDefineOverloadTemplate = false;

static struct OverloadedFunction
{
    string returnType;
    string argsTypes;
    string argsParams;
    string cimguiFunc;
}

static struct Function
{
    string owner;
    string name;
    bool exists;
    bool willForward;

    @property string fname()
    {
        if(owner == "")
            return name;
        else
            return owner~"_"~name;
    }
    OverloadedFunction[] overloads;
}

string[] ignoreList =
[
    "ImVector_ImVector",
    "ImVector_back",
    "ImVector_begin",
    "ImVector_end",
    "ImVector_erase",
    "ImVector_find",
    "ImVector_front",
    "ImVector_resize"
];

bool isOnIgnoreList(string line)
{
    foreach(ignore;ignoreList)
        if(line.countUntil(ignore) != -1)
            return true;
    return false;
}

bool hasVarArgs(string params)
{
    return params.countUntil("...") != -1;
}

static Function[] getFunctions(File file)
{
    Function[] ret;
    ret.reserve(128);

    Function func;
    foreach(int i, string line; lines(file))
    {
        int firstCharValue = line[0];
        if(firstCharValue == '-')
            continue;
        if(firstCharValue >= '0' && firstCharValue <= '9' && func.exists)
        {
            string[] infos = line.split();
            if(infos[1] == "overloaded")
                return ret~= func;
            else
            {
                OverloadedFunction overload;
                if(infos[1] == "nil")
                    overload.returnType = func.owner;
                else
                    overload.returnType = infos[1];
                long constInd = infos.countUntil("const");
                int infoIndex = 2;
                if(constInd != -1)
                {
                    overload.returnType~= " "~infos[constInd+1];
                    infoIndex++;
                }
                overload.cimguiFunc = infos[infoIndex];
                
                // long argsStart = line.countUntil("("); //Not used anymore
                getParameters(func, overload);
                // overload.argsTypes = line[cast(uint)argsStart..line.length];
                func.overloads~= overload;
            }
        }
        else
        {
            if(func.exists)
                ret~= func;
            func = Function();
            string[] infos = line.split("_"); //Gets the function name
            if(isOnIgnoreList(line))
            {
                func.exists = false;
                continue;
            }
            int nameIndex = 0;
            if(infos.length != 1)
            {
                func.owner = infos[0];
                nameIndex = 1;
                long separatorIndex = infos[nameIndex].countUntil("\t");
                if(separatorIndex == -1)
                    separatorIndex = infos[nameIndex].countUntil(" ");
                if(separatorIndex == -1)
                    return null;
                func.name = infos[nameIndex][0..cast(uint)separatorIndex];
            }
            else
            {
                infos = line.split();
                func.owner = "";
                func.name = infos[0];
            }
            
            
            func.exists = true;
        }
    }
    return ret;
}

string generateAliasOverload()
{
return q{
static template overload(Func...)
{
    import std.traits;
    static foreach(f; Funcs)
        auto overload(Parameters!f params){
            return f(params);}
}};
}

static void getParameters(ref Function func, ref OverloadedFunction overload)
{
    JSONValue jsonFunc = defs[func.fname].array;
    foreach (JSONValue ovFunc; jsonFunc.array)
    {
        if(ovFunc["ov_cimguiname"].str == overload.cimguiFunc)
        {

            overload.argsTypes = ovFunc["argsoriginal"].str;
            if(hasVarArgs(overload.argsTypes))
            {
                func.willForward = true;
            }
            overload.argsParams = "(";
            JSONValue argParams = ovFunc["argsT"];
            size_t len = argParams.array.length;
            foreach(i, params; argParams.array)
            {
                overload.argsParams~= params["name"].str;
                if(i+1 != len)
                    overload.argsParams~=",";
            }
            overload.argsParams~= ")";
            break;
        }
    }
}

static string generateOverloads(Function[] funcs)
{
    string fileContent = "";
    string line = "";
    import std.format:format;

    string funcName;
    foreach(func; funcs)
    {
        funcName = func.name;
        if(func.willForward)
        {
            if(!willDefineOverloadTemplate)
                willDefineOverloadTemplate = true;
            line = "alias "~funcName ~"= overload!(";
            string comment = "/**\n";
            foreach(i, ov ; func.overloads)
            {
                comment~= "*\t"~ov.returnType~" "~funcName~ov.argsTypes~"\n";
                line~= ov.cimguiFunc;
                if(i != func.overloads.length - 1)
                    line~=",";
                //Write a comment on the alias for appearing 
            }
            comment~="*/\n";
            fileContent~= comment~line~");\n";
        }
        else foreach(overload; func.overloads)
        {
            line = overload.returnType~" "~funcName~overload.argsTypes~"{"~overload.cimguiFunc;
            line~= overload.argsParams~";}";
            fileContent~= line~"\n";
        }
    }
    return fileContent;
}


static JSONValue defs = null;
//Will only receive the path to overloads.txt

string getOverloadsPath(string cimguiPath)
{
    return cimguiPath~"/generator/output/overloads.txt";
}
string getDefinitionsPath(string cimguiPath)
{
    return cimguiPath~"/generator/output/definitions.json";
}


class CimGuiOverloadPlugin : Plugin
{
    string storedStr;
    override string target(){return "cimgui-overloads";}
    override string convertToD_Pipe()
    {
        return storedStr;
    }
    string outputPath;
    override int main(string[] args)
    {
        
        if(args.length < 2)
            return returnError("Argument Expected:\nNo path for cimgui provided!");
        else if(args.length == 3)
            outputPath = args[2];
        string cimguiPath = args[1];
        if(!exists(cimguiPath))
            return returnError("Cimgui directory '"~cimguiPath~"' not found");
        string overloads = getOverloadsPath(cimguiPath);
        string defsPath = getDefinitionsPath(cimguiPath);

        if(!exists(overloads))
            return returnError("Overloads path '"~overloads~"' does not exists");
        if(!exists(defsPath))
            return returnError("Definitions path '"~defsPath~"' does not exists");
        
        defs = parseJSON(readText(defsPath));

        File f = File(overloads);
        Function[] funcs = getFunctions(f);
        storedStr = generateOverloads(funcs);

        return Plugin.SUCCESS;
    }
    override int onReturnControl(string processedStr)
    {
        import std.file : write;
        string s = "module bindbc.cimgui.overloads;\n\n";
        s~= "import bindbc.cimgui.funcs;\n";
        if(willDefineOverloadTemplate)
            s~= generateAliasOverload();
        s~="\n";
        

        write("overloads.d", s~processedStr);
        return Plugin.SUCCESS;
    }
    override string getHelpInformation()
    {
        return r"This plugin was made to be used in conjunction with BindBC-Generator, located on
https://github.com/MrcSnm/bindbc-generator

1: Argument must be 'cimgui' path, it will look for definitions.json and overloads.txt 
2(Optional): Output path";
    }

}

extern(C) export Plugin exportOverloadgen()
{
    return new CimGuiOverloadPlugin();
}
