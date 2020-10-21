module overloadgen;
import plugin;
import std.stdio;
import std.json;
import std.array : split;
import std.algorithm : countUntil;
import std.file : readText, exists;


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

    @property string fname()
    {
        if(owner == "")
            return name;
        else
            return owner~"_"~name;
    }
    OverloadedFunction[] overloads;
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
                overload.cimguiFunc = infos[2];
                
                long argsStart = line.countUntil("(");
                getParameters(func, overload);
                // overload.argsTypes = line[cast(uint)argsStart..line.length];
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

static void getParameters(ref Function func, ref OverloadedFunction overload)
{
    JSONValue jsonFunc = defs[func.fname].array;
    foreach (JSONValue ovFunc; jsonFunc.array)
    {
        if(ovFunc["ov_cimguiname"].str == overload.cimguiFunc)
        {

            overload.argsTypes = ovFunc["argsoriginal"].str;
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
        foreach(overload; func.overloads)
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
    override int main(string[] args)
    {
        if(args.length < 2)
            return returnError("Argument Expected:\nNo path for cimgui provided!");
        string cimguiPath = args[1];
        if(!exists(cimguiPath))
            return returnError("Cimgui directory '"~cimguiPath~"' not found");
        string overloads = getOverloadsPath(cimguiPath);
        string defsPath = getDefinitionsPath(cimguiPath);

        if(!exists(overloads))
            return returnError("Overloads path '"~overloads~"' does not exists");
        if(!exists(defsPath))
            return returnError("Definitions path '"~defsPath~"' does not exists");
        
        writeln("Hello!");
        defs = parseJSON(readText(args[2]));

        File f = File(overloads);
        Function[] funcs = getFunctions(f);
        storedStr = generateOverloads(funcs);

        return Plugin.SUCCESS;
    }
    override void onReturnControl(string processedStr)
    {
        writeln(processedStr);
    }
    override string getHelpInformation()
    {
        return r"This plugin was made to be used in conjunction with BindBC-Generator, located on
https://github.com/MrcSnm/bindbc-generator

The argument must be 'cimgui' path, it will look for definitions.json and overloads.txt ";
    }

}

extern(C) export Plugin exportOverloadgen()
{
    return new CimGuiOverloadPlugin();
}
