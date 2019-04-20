/*----------------------------------------------
 *   ___ ___     ___ ___ _   _ ___ _  _ 
 *  / __|   \   / __| _ \ | | / __| || |
 * | (__| |) | | (__|   / |_| \__ \ __ |
 *  \___|___/   \___|_|_\\___/|___/_||_|
 * 
 * == CDCRUSH.hx
 * @author: JohnDimi, <johndimi@outlook.com>
 * ----------------------------------------------
 * - CDCRUSH main engine class
 * ----------------------------------------------
 * 
 * ---------------------------------------------- */

package;
import cd.CDInfos;
import djNode.task.CJob;
import djNode.task.CJob.CJobStatus;
import djNode.tools.FileTool;
import djNode.tools.LOG;
import djNode.tools.StrTool;
import js.Error;
import js.Node;
import js.node.Fs;
import js.node.Os;
import js.node.Path;




class CDCRUSH
{
	//====================================================;
	// SOME STATIC VARIABLES 
	//====================================================;
	
	// -- Program Infos
	public static inline var AUTHORNAME = "John Dimi";
	public static inline var PROGRAM_NAME = "cdcrush";
	public static inline var PROGRAM_VERSION = "1.5";
	public static inline var PROGRAM_SHORT_DESC = "Highy compress cd-image games";
	public static inline var LINK_DONATE = "https://www.paypal.me/johndimi";
	public static inline var LINK_SOURCE = "https://github.com/johndimi/cdcrush";
	public static inline var CDCRUSH_SETTINGS = "crushdata.json";
	public static inline var CDCRUSH_COVER = "cover.jpg";	// Unused in CLI modes
	
	public static inline var CUE_EXTENSION = ".cue";
	
	// When restoring a cd to a folder, put this at the end of the folder's name
	public static inline var RESTORED_FOLDER_SUFFIX = " (r)";	
	
	// The temp folder name to create under `TEMP_FOLDER`
	// No other program in the world should have this unique name, right?
	// ~~ Shares name with the C# BUILD
	public static inline var TEMP_FOLDER_NAME = "CDCRUSH_361C4202-25A3-4F09-A690";
	
	// Keep temporary files, don't delete them
	// Useful for debugging
	public static var FLAG_KEEP_TEMP:Bool = false;
	
	// Maximum concurrent tasks in CJobs
	public static var MAX_TASKS(default, null):Int = 3;
	
	// Is FFMPEG ready to go?
	public static var FFMPEG_OK(default, null):Bool;
	
	// FFMPEG path
	public static var FFMPEG_PATH(default, null):String;

	// Relative directory for the external tools (Arc, EcmTools)
	public static var TOOLS_PATH(default, null):String;

	// This is the GLOBAL Temp Folder used for ALL operations
	public static var TEMP_FOLDER(default, null):String;
		
	// General use Error Message, read this to get latest errors from functions
	//public static var ERROR(default, null):String;	
	
	
	/**
	   Initialize CDCRUSH 
	   @param	tempFolder
	**/
	public static function init(?tempFolder:String)
	{
		LOG.log('== ' + PROGRAM_NAME + ' - v ' + PROGRAM_VERSION);
		LOG.log('== ' + PROGRAM_SHORT_DESC);
		#if EXTRA_TESTS
		LOG.log('== DEFINED : EXTRA_TESTS');
		LOG.log('== > Will do extra checksum checks on all operations.');
		#end
		LOG.log('== ------------------------------------------------- \n\n');
		
		#if debug
			// When running from `source/bin/`
			TOOLS_PATH = "../tools/";		
			FFMPEG_PATH = "";
		#else  
			// NPM BUILD :
			// Same folder as the main .js script :
			TOOLS_PATH = FileTool.appFileToFullPath("");
			FFMPEG_PATH = "";		
		#end
		
		#if STANDALONE
			// Everying is included in 
			TOOLS_PATH = "tools/";
			FFMPEG_PATH = "tools/";
		#end
		
		CDInfos.LOG = (l)->{LOG.log(l);}
		
		setTempFolder(tempFolder);
	}//---------------------------------------------------;
	
	// --
	public static function setThreads(t:Int)
	{
		if (t > 8) t = 8 else if (t < 1) t = 1;
		MAX_TASKS = t;
		LOG.log("== MAX_TASKS = " + MAX_TASKS);
	}//---------------------------------------------------;
	
	/**
	   Try to set a temp folder, Returns success
	   @param	f The ROOT folder in which the temp folder will be created
	   @return  SUCCESS 
	**/
	public static function setTempFolder(?tmp:String)
	{
		var TEST_FOLDER:String;
		
		if (tmp == null) tmp = Os.tmpdir();
		
		TEST_FOLDER = Path.join(tmp, TEMP_FOLDER_NAME);
		
		try{
			FileTool.createRecursiveDir(TEST_FOLDER);
		}catch (e:String){
			LOG.log("Can't Create Temp Folder : " + TEST_FOLDER, 4);
			LOG.log(e, 4);
			throw "Can't Create Temp Folder : " + TEST_FOLDER;
		}
		
		// Write Access
		if (!FileTool.hasWriteAccess(TEST_FOLDER))
		{
			throw "Don't have write access to Temp Folder : " + TEST_FOLDER;
		}
		
		TEMP_FOLDER = TEST_FOLDER;
		LOG.log("+ TEMP FOLDER = " + TEMP_FOLDER);
	}//---------------------------------------------------;
	
	/**
	   Check if path exists and create it
	   If it exists, rename it to a new safe name, then return the new name
	**/
	public static function checkCreateUniqueOutput(A:String, B:String = ""):String
	{
		var path:String = "";
		
		try{
			path = Path.join(A, B);
		}catch (e:Error){
			throw 'Can`t join paths ($A + $B)';
		}
		
		while (FileTool.pathExists(path))
		{
			path = path + "_";
			LOG.log("! OutputFolder Exists, new name: " + path);
		}
	
		// Path now is unique
		try{
			FileTool.createRecursiveDir(path);
		}catch (e:String){
			throw "Can't create " + path;
		}
	
		// Path is created OK
		return path;
	}//---------------------------------------------------;
	
	/**
	   Check if file EXISTS and is of VALID EXTENSION
	   @Throws
	   @param ext Extension WITH "."
	**/
	public static function checkFileQuick(file:String, ext:String)
	{
		if (!FileTool.pathExists(file))
		{
			throw "File does not exist " + file;
		}
		
		if (Path.extname(file).toLowerCase() != ext)
		{
			throw "File, not valid extension " + file;
		}

	}//---------------------------------------------------;

	// --
	// Get a unique named temp folder ( inside the main temp folder )
	public static function getSubTempDir():String
	{
		return Path.join(TEMP_FOLDER , StrTool.getGUID().substr(0, 12));
	}//---------------------------------------------------;

}// -- end class



//====================================================;
// TYPES 
//====================================================;



/**
   Object storing all the parameters for :
   - CRUSH job
   - CONVERT job
**/
typedef CrushParams = {
	
	// The CUE file to compress
	inputFile:String,
	// Output Directory, The file will be autonamed
	// ~ Optional ~ Defaults to the directory of the `inputfile`
	?outputDir:String,
	// Audio Settings String (e.g OPUS:1, MP3:1) Null for default ( defined in CodecMaster )
	?ac:String,
	// Data Compression String (e.g. 7Z:2, ARC ) Null for default ( defined in CodecMaster )
	?dc:String,
	// Do not Create Archive, Just Convert Audio Tracks (USED in `JobConvert`)
	?flag_convert_only:Bool,

	// -- Internal Access -- //
	
	//// Keep the CD infos of the CD, it is going to be read later
	//cd:CDInfos,
	//// Filesize of the final archive
	//crushedSize:Int,
	//// Temp dir for the current batch, it's autoset, is a subfolder of the master TEMP folder.
	//tempDir:String,
	//// Final destination ARC file, autogenerated from CD TITLE
	//finalArcPath:String,
	//// If true, then all the track files are stored in temp folder and safe to delete
	//flag_sourceTracksOnTemp:Bool,
	//
	//// Used for reporting back to user
	//convertedCuePath:String,
	
}// --



/**
   Object storing all the parameters for 
   - RESTORE job
**/
class RestoreParams
{
	public function new(){}
	// -- Input Parameters -- //
	
	// The file to restore the CDIMAGE from
	public var inputFile:String;
	
	// Output Directory. Will change to subfolder if `flag_folder`
	// ~ Optional ~ Defaults to the directory of the `inputfile`
	public var outputDir:String;
	
	// TRUE: Create a single cue/bin file, even if the archive was MULTIFILE
	public var flag_forceSingle:Bool;
	
	// TRUE: Create a subfolder with the game name in OutputDir
	public var flag_subfolder:Bool;
	
	// TRUE: Will not restore audio tracks to PCM. Will create CUE with Encoded Audio Files
	public var flag_encCue:Bool;
	
	// : Internal Use :

	// Temp dir for the current batch, it's autoset by Jobs
	// is a subfolder of the master TEMP folder
	public var tempDir:String;
	// Keeps the current job CDINfo object
	public var cd:CDInfos;
	
	// Used for reporting back to user
	public var createdCueFile:String;
	
}// --