module pluginadapter;
import plugin;
import std.stdio;
import std.string;
import std.file;
import std.path;
import std.conv:to;
import std.process;


string[][] getExportedFunctions()
{
    if(!exists("plugins"))
    {
        writeln("\n\nplugins folder not found! Setting up plugins folder");
        mkdir("plugins");
        return [[]];
    }
    string[][] exporteds;
    foreach(string file; dirEntries("plugins", SpanMode.shallow))
    {
        if(isDir(file))
        {
            exporteds~= [file.baseName];
            foreach(DirEntry plugin; dirEntries(file, "*.d", SpanMode.shallow))
            {
                if(plugin.isFile)
                {
                    exporteds[exporteds.length - 1]~= plugin.name.stripExtension.baseName.capitalize;
                }
            }
        }
    }
    return exporteds;
}


version(Posix)
{
    void* _dlopen(const scope char* dllName)
    {
        import core.sys.posix.dlfcn : dlopen, RTLD_LAZY;
        return dlopen(dllName, RTLD_LAZY);
    }
}



class PluginAdapter
{
    static Plugin[string] loadedPlugins;

    static Plugin function()[] loadFuncs;


    static void*[] dlls;

    version(Windows)
    {
        import core.sys.windows.windows;
        static alias loadDLL = LoadLibraryA;
        static const (char)* err;
        static void* symbolLink(void* dll, const (char)* symbolName)
        {
            void* ret = GetProcAddress(dll, symbolName);
            import std.conv:to;
            if(!ret)
                err = ("Could not link symbol "~to!string(symbolName)).ptr;
            return ret;
        }
        static const(char)* dllError()
        {
            const(char)* ret = err;
            err = null;
            return ret;
        }
    }
    else version(Posix)
    { 
        import core.sys.posix.dlfcn;
        static alias loadDLL = _dlopen;
        static alias symbolLink = dlsym;
        static alias dllError = dlerror;
    }
    else pragma(msg, "Current system does not support dll loading! Implement it yourself or open a new issue!");

    
    version(Posix)static const (char)* getPackName(string packName)
    {
        return "libplugin"~packName~".so";
    }
    version(Windows)static const (char)* getPackName(string packName)
    {
        return ("libplugin"~packName~".dll").ptr;
    }

    static void loadDLLFunc(void* dll, string pluginName)
    {
        void* symbol = symbolLink(dll, ("export"~pluginName).ptr);
        const(char)* error = dllError();
        if(error)
            writeln("Dynamic Library symbol link error: ", to!string(error));
        else
        {
            Plugin function() getClass = cast(Plugin function())symbol;
            Plugin p = getClass();
            loadedPlugins[p.target] = p;
            writeln("Loaded plugin '", p.target, "'");
        }
    }

    static bool compilePluginDLL(string[] files)
    {
        import std.algorithm : countUntil;
        if(countUntil(files, "Package") == -1)
        {
            writeln("package not found, creating it.");
            string pkg;
            import std.format : format;
            import std.uni : toLower;
            pkg = "module "~ files[0]~";\n";
            pkg~="import plugin;";
            for(size_t i = 1, len = files.length; i < len; i++)
            {
                if(files[i] != "Package") //Remember extension was stripped and it is capitalized 
                    pkg~="\npublic import " ~ toLower(files[i])~";";
            }
            pkg~= "\n\nmixin PluginLoad;";
            std.file.write("plugins/"~files[0]~"/package.d", pkg);
        }
        
        string packName = to!string(getPackName(files[0]));
        string[] compileCommand = 
        [
            "dmd", "-shared", 
            "-odplugins/"~files[0]~"/obj",
            "-ofplugins/"~files[0]~"/"~packName
        ];
        version(X86){compileCommand~= "-m32";}
        else version(X86_64){compileCommand~= "-m64";}
        else
        {
            writeln("Architecture unknown, omitting architecture command for compiler");
        }
        version(Windows)
        {
            //DLL Specific things.
            string dllDef = "LIBRARY \"" ~ packName~"\"\n";
            dllDef~="EXETYPE NT\n";
            dllDef~="SUBSYSTEM WINDOWS\n";
            dllDef~="CODE SHARED EXECUTE\n";
            dllDef~="DATA WRITE";
            string dllDefName = "plugins/"~files[0]~"/"~packName.stripExtension~".def";
            if(!exists(dllDefName))
                std.file.write(dllDefName, dllDef);
            compileCommand~=dllDefName;
            
        }
        compileCommand~= "source/plugin.d";
        string path = "plugins/"~files[0]~"/";
        for(size_t i = 1, len = files.length; i < len; i++)
        {
            compileCommand~= path~toLower(files[i])~".d";
        }
        writeln("Executing command '", compileCommand, "'");
        auto ret = execute(compileCommand);
        if(ret.status != 0)
            writeln("DMD Log: \n\n\n", ret.output, "\n\n\n");
        return true;
    }

    static void loadPlugins()
    {
        string[][] funcs = getExportedFunctions();

        for(ulong i = 0, len = funcs.length; i < len; i++)
        {
            string packName = to!string(getPackName(funcs[i][0]));
            string path = "plugins/"~funcs[i][0]~"/";
            if(!exists(path~packName))
            {
                writeln(packName, " does not exists. Invoke dmd? y/n");
                if(readln() == "y\n")
                    compilePluginDLL(funcs[i]);
                else
                    return writeln("Compile the dll first!");
            }
            void* dll = loadDLL((path~packName).ptr);
            if(dll == null)
            {
                writeln("Could not load ", path~packName);
                continue;
            }
            else
                dlls~= dll;
            for(ulong j = 1, len2 = funcs[i].length; j < len2; j++)
            {
                if(funcs[i][j] == "Package")
                    continue;
                loadDLLFunc(dll, funcs[i][j]);
            }
            
        }
    }    
}