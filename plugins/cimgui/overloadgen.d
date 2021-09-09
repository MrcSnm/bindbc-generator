module overloadgen;
import plugin;
import std.path;
import std.process : executeShell;
import std.stdio;
import std.json;
import std.array : split, array;
import std.file;
import std.algorithm : countUntil;

bool willDefineOverloadTemplate = false;

static struct OverloadedFunction
{
    string pOutType;
    string returnType;
    string argsTypes;
    string argsParams;
    string cimguiFunc;

    string[string] callbackAliases;
    bool isTemplated;
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
    "ImPool_Remove",
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

bool hasTemplateArgs(string params)
{
    for(int i = 0; i < params.length; i++)
        if(params[i] == 'T' && (params[i+1] == ' ' || (params[i+1] == '*' && params[i+2] == ' ')))
            return true;
    return false;
}

static Function[] getFunctions(File file)
{
    Function[] ret;
    ret.reserve(128);

    Function func;
    foreach(int i, string line; lines(file))
    {
        int firstCharValue = line[0];
        if(firstCharValue == '-') //Is begin or end of file
            continue;
        //If is an overload ID and the function is not being ignored
        if(firstCharValue >= '0' && firstCharValue <= '9' && func.exists)
        {
            string[] infos = line.split();
            if(infos[1] == "overloaded")
                return ret~= func;
            else
            {
                OverloadedFunction overload;
                if(infos[1] == "nil") //Returns an instance
                    overload.returnType = func.owner~"*";
                else if(infos[1] == "T" || infos[1] == "T*")
                {
                    overload.isTemplated = true;
                    overload.returnType = infos[1];
                }
                else
                    overload.returnType = infos[1];
                long constInd = infos.countUntil("const");
                int infoIndex = 2;
                if(constInd != -1) //Add const with parenthesis
                {
                    overload.returnType~= " ("~infos[constInd+1]~")";
                    if(infos[constInd+1] == "T" || infos[constInd+1] == "T*")
                        overload.isTemplated = true;
                    infoIndex++;
                }
                //Next index is the cimgui bound name
                overload.cimguiFunc = infos[infoIndex];

                ///May set function as templated                
                getParameters(func, overload);
                func.overloads~= overload;
            }
        }
        else //Not a overload, it is defining overloads for a function
        {
            if(func.exists) //If there is already one function that was being defined, append it
                ret~= func;
            func = Function();
            string[] infos = line.split("_"); //Gets the function name
            if(isOnIgnoreList(line))
            {
                func.exists = false;
                continue;
            }
            int nameIndex = 0;
            if(infos.length != 1) //If it has an underline, it is a member function
            {
                //Member functions has owner
                func.owner = infos[0];
                nameIndex = 1;
                long separatorIndex = infos[nameIndex].countUntil("\t"); //Try to advance if the next char is \t
                if(separatorIndex == -1)
                    separatorIndex = infos[nameIndex].countUntil(" ");  //Try to advance a space
                if(separatorIndex == -1) //No overload
                    return null;
                func.name = infos[nameIndex][0..cast(uint)separatorIndex]; //Gets the name by removing the number of overloads
            }
            else //No owner as there is not _
            {
                infos = line.split();
                func.owner = "";
                func.name = infos[0];  //After splitting, always located at 0
            }
            func.exists = true;
        }
    }
    return ret;
}

string generateAliasOverload()
{
return q{
import core.stdc.stdarg;
static template overload(Funcs...)
{
    import std.traits : Parameters;
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

            //Check for callback to preppend extern(C)
            string argsTypes = "";
            long ind = 0; 
            long nextInd = 0;
            import std.string:indexOf;

            overload.argsTypes = ovFunc["args"].str;

            func.willForward = hasVarArgs(overload.argsTypes);
            if(!overload.isTemplated) overload.isTemplated = hasTemplateArgs(overload.argsTypes);
            
            overload.argsParams = "(";
            JSONValue argParams = ovFunc["argsT"];
            size_t len = argParams.array.length;
            foreach(i, params; argParams.array)
            {
                overload.argsParams~= params["name"].str;
                string aliasName;

                if(const(JSONValue)* ret = "ret" in params) //Is a callback
                {
                    // argsTypes~= "extern(C) ";
                    //Move current string index pointer 2 times to ) (as the callback must have at )
                    //I'll not deal with callback that receives a callback as it is too complex and unnecessary 
                    nextInd = indexOf(overload.argsTypes, ')', nextInd)+1;
                    nextInd = indexOf(overload.argsTypes, ')', nextInd)+1;

                    string callbackSignature = overload.argsTypes[ind..nextInd];
                    long startCb = callbackSignature.indexOf("(");
                    long endCb = callbackSignature.indexOf(")");

                    //Generate the callback signature (D converted already) for alias definition
                    callbackSignature = "extern(C) "~callbackSignature[0..startCb] ~ " function "~callbackSignature[endCb+1..$];
                    ///Alias name based on argument name
                    aliasName = func.name~"_"~params["name"].str;
                    overload.callbackAliases[callbackSignature] = aliasName;

                }
                //Check if it has more parameters
                long nextIndTemp = indexOf(overload.argsTypes, ",", nextInd);
                if(nextIndTemp == -1) //Seek the function end if not
                    nextIndTemp = indexOf(overload.argsTypes, ")", nextInd);
                nextInd = nextIndTemp+1;

                if(params["name"].str == "pOut") //For returning it later
                {
                    overload.pOutType = params["type"].str;
                }
                else if(aliasName)
                    argsTypes~= aliasName ~" "~params["name"].str~ (i+1 != len ? ", " : "");
                else
                    argsTypes~= overload.argsTypes[ind..nextInd];
                ind = nextInd;
                if(i+1 != len)
                    overload.argsParams~=","; //Add comma if not at the end
            }
            if(argsTypes != "")
            {
                overload.argsTypes = argsTypes;
                if(overload.argsTypes[0] != '(')
                    overload.argsTypes = "("~overload.argsTypes;
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
        line=null;
        funcName = func.name;
        if(funcName == func.owner)
            funcName = "new"~funcName;
        else if(func.owner != "")
            funcName = func.owner~"_"~func.name;
        if(func.willForward)
        {
            if(!willDefineOverloadTemplate)
                willDefineOverloadTemplate = true;
            line= "alias "~funcName ~"= overload!(";
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
            //The key is the signature, the value is the name
            foreach(callbackKey, callbackValue; overload.callbackAliases)
                line = "\nalias "~callbackValue ~" = "~callbackKey~";\n";
            if(overload.isTemplated)
                line~= overload.returnType~" "~funcName~"(T)"~overload.argsTypes~"{";
            else
                line~= overload.returnType~" "~funcName~overload.argsTypes~"{";
            if(overload.returnType != "void")
            {
                if(overload.pOutType == "")
                    line~= "return ";
                else //Create pOut ret
                {
                    long asteriskIndex = countUntil(overload.pOutType, "*");
                    line~= overload.pOutType[0..asteriskIndex] ~ " pOut;\t";
                }
            }
            line~=overload.cimguiFunc;
            line~= overload.argsParams;
            if(overload.pOutType != "")
            {
                line~=";\t return pOut";
            }
            line~=";}";
            fileContent~= line~"\n";
            line=null;
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


string injectRefOnPOut(string fileContent)
{
    string tempFileContent = fileContent;
    string newFileContent;
    long pOutIndex = countUntil(fileContent, "pOut,");
    static long len = "pOut,".length;
    while(pOutIndex != -1)
    {
        tempFileContent = tempFileContent[0..pOutIndex];
        newFileContent~=tempFileContent~"&pOut,";
        fileContent = fileContent[pOutIndex+len..$];
        tempFileContent = fileContent;
        pOutIndex = countUntil(tempFileContent, "pOut,");
    }

    return newFileContent~fileContent;
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
        import std.string;
        if (args.length == 2 && args[1].startsWith(`"[`))
        {
            auto newArgs = [args[0]];
            newArgs ~= args[1][2..$-2].split(" ");
            args = newArgs;
        }
        writeln(args);

        if(args.length < 2)
            return returnError("Argument Expected:\nNo path for cimgui folder provided!");
        else if(args.length == 3)
            outputPath = args[2];
        string cimguiPath = args[1];
        import std.path;
        
        if(!exists(cimguiPath))
        {
            string temp = absolutePath(cimguiPath);
            writeln("Checking if ", temp, " exists");
            if(exists(temp))
            {
                cimguiPath = temp;
            }
            else
                return returnError("Cimgui directory '"~cimguiPath~"' not found");
        }
        string overloads = getOverloadsPath(cimguiPath);
        string defsPath = getDefinitionsPath(cimguiPath);

        if(!exists(overloads))
        {
            writeln("Overloads does not exists yet. Overloadgen will try to generate the overload");
            string toTest = (overloads~"../../").asNormalizedPath.array;
            if(exists((toTest~"/generator.bat").asNormalizedPath.array))
            {
                version(Windows){executeShell(readText(toTest~"\\generator.bat"));}
                else{executeShell(readText(toTest~"\\generator.sh"));}
            }
            else
                return returnError("Overloads path '"~overloads~"' does not exists");
        }
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
        s~= "import bindbc.cimgui.types;\n";
        if(willDefineOverloadTemplate)
            s~= generateAliasOverload();
        s~="\n";

        //Search for pOuts on processedStr for putting & 
        
        processedStr = injectRefOnPOut(processedStr);
        writeln("Writing overloads.d to the path '" ~ outputPath~"'");
        if(outputPath)
        {
            mkdirRecurse(outputPath);
            write(buildPath(outputPath, "overloads.d"), s~processedStr);
        }
        else
            write("overloads.d", s~processedStr);
        return Plugin.SUCCESS;
    }
    override string getHelpInformation()
    {
        return r"This plugin was made to be used in conjunction with BindBC-Generator, located at
https://github.com/MrcSnm/bindbc-generator

1: The path to 'cimgui'; it will look for definitions.json and overloads.txt.
2(Optional): Output path";
    }

}

extern(C) export Plugin exportOverloadgen()
{
    return new CimGuiOverloadPlugin();
}
