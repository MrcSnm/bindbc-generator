module plugin;

/**
*   Plugins must be made for a post-task for presets on generate.d
*   I don't still have much experience on how should I do it, but following a pattern will
*   really help at those things
*/
abstract class Plugin
{
    static int SUCCESS = 1;
    static int ERROR = 0;
    abstract string target();
    abstract int main(string[] args);
    abstract void postTask();
    Plugin[] pluginHooks;
}

mixin template PluginLoad()
{
    import core.sys.windows.dll:SimpleDllMain;
    mixin SimpleDllMain;
}