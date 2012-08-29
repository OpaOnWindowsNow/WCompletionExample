/* Example of WCompletion use, with all computation on client side */

import stdlib.widgets.completion
import stdlib.io.file


/* a dictionnay represent all possible result of the completion */
type dictionnary = list(string) // a very simple dictionnay implementation, pick something more powerfull if you have big dictionnary
search_dict(prefix,dict) =
  match_prefix = String.has_prefix(String.to_lower(prefix),_)
  List.filter( match_prefix, dict)

string_to_suggestion(s:string):WCompletion.suggestion = {input=s display=<>{s}</> item=s}

@server_private
dict =  String.explode("\n",  string_of_binary(File.content("english.0")) ) ++ [ "tic","tac","isidor" ]
// if opa version < 3230 use a smaller dictionnary with nodejs backend, e.g. List.init( _ -> Random.string(8), 1000 )

/* the dictionnay computation is a server operation, could be the db for instance */
// server_private is equivalent to protected in js-like syntax
@server_private
mydictionnary() = dict

/*
   The central element of the completion widget is the suggest function that is part of the widget configuration.
   This configuration is almost always constructed on server side.
   If you take no particular precaution it means that the suggest function of the configuration will come from the server.
   For both security and efficiency reason, there is no guaranty that the client has the function (space conservation), should have access to the environment of the function (if any) client.
   It means that the client will have to call the server to execute the suggest function.
   In the case of the completion widget, it means that any keystroke will triggered a communication between the client and the server.
   So you need to ensure that the client don't need to call the server to execute the suggest function.
   We also add the constraint that the client does not possess the dictionnary defining the completion (so it must come from the server).
   To indicates that the function should be exhanged from the server to the client without needing the server we must authorize the publication of its environment.
   This is done using @public_env directive.
*/


/* Solution 1
   The dictionnary will be embedded in the environment of suggest function, so it's content will be fixed at creation of the configuration */
WithPlainDictionnary = {{


  /* simple dictionnay search */
  suggest_with_dict(prefix, dict) = List.map(string_to_suggestion ,search_dict(prefix,dict))

  /* creating a function to search on a particular dictionnay, the function is suitable for server to client exchange
     here @public_env ensures the client will have access to anything compute a call to
     the partial application <suggest_with_dict(_, dict)> on client side
     This mean the code for suggest_with_dict and the dictionnary can be transfered from the server to the client.
  */
  create_suggest(dict) = @public_env(suggest_with_dict(_, dict))

}}

/* Solution 2
   The suggest function have access to a storage on client side to put the dictionnary in and use it wihtout needing the server.
   So the dictionnary will be asked only once.
   It is alse more flexible because you can have different policy to use only a partial dictionnary or evolving one */
WithCache = {{


  // Accessing a dictionnary filtered by a prefix
  // Note the publish (<=> exposed in js-like syntax) directive, it create an entry point to access mydictionnary from the client
  // and it stops propagation of the server_private property, => stripped_dictionnary and its caller are not server_private 
  @publish
  stripped_dictionnary(prefix) =
    mydictionnary()
    |> List.map( String.to_lower, _ )
    |> search_dict(prefix, _ )


  // storage for the client local sub-dictionnary (only valid for the given prefix)
  @private
  @client
  cache_dictionnary = Mutable.make(none : option({prefix:string dict:list(string)}))

  size_to_get_dictionnary = 3 // minimal number of letter to fill the cache
  size_to_get_completion = size_to_get_dictionnary + 0 // minimal number of letter of letter to have a completion

  // Remark : this function could consider updating the cache if it is older that some long time for dictionnary that change during the interaction
  /* a suggest function that fills the cache if needed or use it
     @public_env ensures the function will available on both side */
  @public_env
  suggest(prefix:string) =
    match cache_dictionnary.get()
    {none} ->
      do if String.length(prefix) >= size_to_get_dictionnary then cache_dictionnary.set(some({~prefix dict=stripped_dictionnary(prefix)}))
      if String.length(prefix) >= size_to_get_completion then suggest(prefix)
      else []
    {some=cache} ->
      if String.has_prefix(cache.prefix, prefix) then WithPlainDictionnary.suggest_with_dict(prefix,cache.dict)
      else do cache_dictionnary.set(none)
           suggest(prefix)

}}

use_cache = true

// a dummy on_select function, note that the same constraint applies, if we want a pure client on_select computation
@public_env on_select(_:string) = void

page() =
  // here we choose one of the solution
  suggest = if use_cache then /* Solution 1 */ WithCache.suggest
                         else /* Solution 2 */WithPlainDictionnary.create_suggest(mydictionnary())
  config = {WCompletion.default_config with ~suggest} // customising the config
  id = Random.string(8) // a random DOM id
  // And now the html content, just a completion widget
  <h1> Completion example </h1>
  <div>{
    WCompletion.html(config, on_select, id, {input="" display=<></> item=""} )
  }</div>


do Server.start( Server.http,
	[
          {title="Completion example" ~page}
        ] <: Server.handler
)

