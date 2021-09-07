module plugin;

/**
*   Plugins must be made for a post-task for presets on generate.d
*   I don't still have much experience on how should I do it, but following a pattern will
*   really help at those things
*/
abstract class Plugin
{
    private import std.stdio : writeln;
    /**
    *   If returned from main, the plugin should be processed
    */
    static int SUCCESS = 1;
    /**
    *   Should not process this plugin
    */
    static int ERROR = 0;
    /**
    *   Target for getting the options inside bindbc-generate
    */
    abstract string target()
    out(r)
    {
        if(r == "")
            writeln("FATAL ERROR:\n\n\nPlugin target can't be null\n");
        // assert(r != "", "FATAL ERROR:\n\n\nPlugin target can't be null\n");
    }
    /**
    *   Gets the error reason
    */
    final int returnError(string err)
    {
        if(err.length <= 20)
            writeln("Please provide better error messages for easier debugging");
        error = err;
        return Plugin.ERROR;
    }
    /**
    *   Whether convertToD_Pipe can be called
    */
    abstract int main(string[] args)
    out(r)
    {
        if(r != Plugin.SUCCESS && r != Plugin.ERROR)
            writeln("Please, use Plugin.SUCCESS or Plugin.ERROR as your return value");
    }
    /**
    *   Executed after main, this is the string to be processed/convert to D style declaration
    */
    abstract string convertToD_Pipe();

    /**
    *   Executed after generate processing
    */
    abstract int onReturnControl(string processedStr);

    /**
    *   Provides help information when every dll is loaded but no argument was passed
    */
    abstract string getHelpInformation()
    out(r)
    {
        if(r == "")
            writeln("Please provide help information");
        else if(r.length <= 50)
            writeln("Help information about plugin is essential\n
            Think if you could elaborate it a bit more!");
    }

    /**
    *   Internal use only, setting up this member yourself will have no effect
    */
    public bool hasFinishedExecution;
    /**
    *   Internal use only
    */
    public bool willConvertToD;
    /**
    *   Set it directly before returning or use returnError function
    */
    public string error;
}

mixin template PluginLoad()
{
    import core.sys.windows.dll : SimpleDllMain;
    mixin SimpleDllMain;
}