module plugin;

/**
*   Plugins must be made for a post-task for presets on generate.d
*   I don't still have much experience on how should I do it, but following a pattern will
*   really help at those things
*/
abstract class Plugin
{
    /**
    *   If it returned from main, the plugin should be processed
    */
    static int SUCCESS = 1;
    /**
    *   Should not process plugin
    */
    static int ERROR = 0;
    /**
    *   Target for getting the options inside bindbc-generate
    */
    abstract string target();
    /**
    *   Wether convertToD_Pipe can be called
    */
    abstract int main(string[] args);
    /**
    *   Executed after main
    */
    abstract string convertToD_Pipe();

    /**
    *   Executed after generate processing
    */
    abstract void onReturnControl(string processedStr);

    abstract string getHelpInformation();
    public bool hasFinishedExecution;
    Plugin[] pluginHooks;
}

mixin template PluginLoad()
{
    import core.sys.windows.dll:SimpleDllMain;
    mixin SimpleDllMain;
}