module pluginadapter;
import plugin;
import std.stdio;
import std.string;
import std.file;
import std.path;
import std.conv:to;
import std.process;


string[][] getExportedFunctions(string pluginFolder)
{
    if(!exists(pluginFolder))
    {
        writeln(pluginFolder ~ "\n\n does not exist! Creating it.");
        mkdirRecurse(pluginFolder);
        return [[]];
    }
    string[][] exporteds;
    foreach(string file; dirEntries(pluginFolder, SpanMode.shallow))
    {
        if(isDir(file))
        {
            exporteds ~= [file.baseName];
            foreach(DirEntry plugin; dirEntries(file, "*.d", SpanMode.shallow))
            {
                if(plugin.isFile)
                {
                    exporteds[exporteds.length - 1] ~= plugin.name.stripExtension.baseName.capitalize;
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
        return ("libplugin"~packName~".so").ptr;
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

    static bool compilePluginDLL(string pluginFolder, string[] files, bool optDebug)
    {
        import std.algorithm : countUntil;

        string firstFilePath = buildPath(pluginFolder, files[0]);

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

            std.file.write(buildPath(firstFilePath, "package.d"), pkg);
        }
        
        string packName = to!string(getPackName(files[0]));
        string[] compileCommand = 
        [
            "dmd", "-shared", 
            "-od" ~ buildPath(firstFilePath, "obj"),
            "-of" ~ buildPath(firstFilePath, packName)
        ];
        if(optDebug)
            compileCommand ~= "-g";
        version(X86){compileCommand ~= "-m32";}
        else version(X86_64){compileCommand ~= "-m64";}
        else
        {
            writeln("Architecture unknown, omitting architecture command for compiler");
        }
        version(Windows)
        {
            //DLL Specific things.
            string dllDef = "LIBRARY \"" ~ packName ~ "\"\n";
            dllDef ~= "EXETYPE NT\n";
            dllDef ~= "SUBSYSTEM WINDOWS\n";
            dllDef ~= "CODE SHARED EXECUTE\n";
            dllDef ~= "DATA WRITE";
            string dllDefName = buildPath(firstFilePath, setExtension(packName, ".def"));
            if(!exists(dllDefName))
                std.file.write(dllDefName, dllDef);
            compileCommand ~= dllDefName;
        }
        compileCommand ~= "source/plugin.d";
        for(size_t i = 1, len = files.length; i < len; i++)
        {
            compileCommand ~= buildPath(firstFilePath, setExtension(toLower(files[i]), ".d"));
        }
        writeln("Executing command '", compileCommand, "'");
        auto ret = execute(compileCommand);
        if(ret.status != 0)
            writeln("DMD Log: \n\n\n", ret.output, "\n\n\n");
        return true;
    }

    static void clean(string dllName)
    {
        string bName = dllName.stripExtension;
        with(std.file)
        {
            writeln(bName);
            if(exists(dllName))
                remove(dllName);
            if(exists(bName~".def"))
                remove(bName~".def");
            if(exists(bName~".exp"))
                remove(bName~".exp");
            if(exists(bName~".lib"))
                remove(bName~".lib");
            if(exists(bName~".pdb"))
                remove(bName~".pdb");
        }
        
    }

    static string[] loadPlugins(string pluginFolder, string[] plugins, bool regenerate, bool optDebug)
    {
        string[][] funcs = getExportedFunctions(pluginFolder);
        import std.algorithm : countUntil;

        string[] pluginsLoaded;
        for(size_t i = 0, len = funcs.length; i < len; i++)
        {
            if(plugins.length != 0 && countUntil(plugins, funcs[i][0]) == -1)
                continue;
            string packName = to!string(getPackName(funcs[i][0]));
            string packPath = buildPath(pluginFolder, funcs[i][0], packName);
            if(!exists(packPath) || regenerate)
            {
                if(!regenerate)
                {
                    writeln(packName, " does not exists. Invoke dmd? y/n");
                    if(readln() == "y\n")
                        compilePluginDLL(pluginFolder, funcs[i], optDebug);
                    else
                    {
                        writeln("Compile the dll first!");
                        continue;
                    }
                }
                else
                {
                    clean(packPath);
                    compilePluginDLL(pluginFolder, funcs[i], optDebug);
                }
            }
            void* dll = loadDLL(packPath.toStringz);
            if(dll == null)
            {
                writeln("Could not load ", packPath);
                continue;
            }
            else
            {
                pluginsLoaded ~= funcs[i][0];
                dlls ~= dll;
            }
            for(ulong j = 1, len2 = funcs[i].length; j < len2; j++)
            {
                if(funcs[i][j] == "Package")
                    continue;
                loadDLLFunc(dll, funcs[i][j]);
            }
            
        }
        return pluginsLoaded;
    }    
}