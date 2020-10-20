module pluginadapter;
import plugin;
import std.stdio;
import std.string;
import std.file;
import std.path;
import std.conv:to;


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
    writeln(exporteds);
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
    static Plugin[] loadedPlugins;

    static Plugin function()[] loadFuncs;

    static void*[] dlls;

    version(Windows)
    {
        import core.sys.windows.windows;
        static alias loadDLL = LoadLibrary;
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
    version(Windows)static const (wchar)* getPackName(string packName)
    {
        return (to!wstring("libplugin"~packName~".dll")).ptr;
    }

    static void loadDLLFunc(void* dll, string pluginName)
    {
        void* symbol = symbolLink(dll, ("export"~pluginName).ptr);
        const(char)* error = dllError();
        if(error)
            writeln("Dynamic Library symbol link error: ", error);
        dlls~= dll;
    }

    static void loadPlugins()
    {
        string[][] funcs = getExportedFunctions();

        for(ulong i = 0, len = funcs.length; i < len; i++)
        {
            void* dll = loadDLL(getPackName(funcs[i][0]));
            if(!dll)
            {
                writeln("Could not load ", to!string(getPackName(funcs[i][0])));
                continue;
            }
            for(ulong j = 0, len2 = funcs[i].length; j < len2; j++)
            {
                loadDLLFunc(dll, funcs[i][j]);

            }

        }
    }    
}