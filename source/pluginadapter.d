module pluginadapter;
import plugin;
import std.stdio;
import std.string;
import std.file;
import std.path;

import core.sys.posix.dlfcn;
import core.sys.windows.dll;

string[][] getExportedFunctions()
{
    if(!exists("plugins"))
    {
        writeln("\n\nplugins folder not found! Setting up plugins folder");
        mkdir("plugins");
        return [[]];
    }
    string[][] exporteds;
    foreach(file; dirEntries("plugins", SpanMode.shallow))
    {
        if(isDir("plugins/"~file))
        {
            exporteds~= ["plugins/"~file];
            foreach(DirEntry plugin; dirEntries("plugins/"~file, SpanMode.shallow))
            {
                if(plugin.isFile)
                {
                    exporteds[exporteds.length - 1]~= plugin.name.stripExtension.capitalize;
                }
            }
        }
    }
    return exporteds;
}




class PluginAdapter
{
    Plugin[] loadedPlugins;

    Plugin function()[] loadFuncs;

    void*[] dlls;

    void loadDLLFunc(string packName, string pluginName)
    {
        void* dll;
        version(Posix)
        {
            dll = dlopen("libplugin"~packName~".so", RTLD_LAZY);
            writeln("DLL was loaded");
            loadFuncs~= cast(Plugin function())dlsym(dll, "export"~pluginName);
            char* error = dlerror();
            if(error)
                writeln("DLsym error: ", error);
        }
        version(Windows)
        {
            
        }
        dlls~= dll;
    }

    void loadPlugins()
    {
        string[][] funcs = getExportedFunctions();

        for(ulong i = 0, len = funcs.length; i < len; i++)
            for(ulong j = 0, len2 = funcs[i].length; j < len2; j++)
                loadDLLFunc(funcs[i][0], funcs[i][j]);
    }    
}