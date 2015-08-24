# rewrites the expressions generated by clang

# dictionary to map pointer types to desired type

type_dict = Dict{Any, Any} (
:PetscScalar => :Float64,
:PetscReal => :Float64,
:PetscInt => :Int32,
)

ptr_dict = Dict{Any, Any} (
:(Ptr{PetscInt}) => :(Union(Ptr{PetscInt}, StridedArray{PetscInt}, Ptr{Void}))
)

ccall_dict = Dict{Any, Any} (
#:Mat => :(Ptr{Void}),
)

function petsc_rewriter(obuf)

  for i=1:length(obuf)
    println("i = ", i)
    ex_i = obuf[i]  # obuf is an array of expressions

    println("ex_i = ", ex_i)
    println("typeof(ex_i) = ", typeof(ex_i))

    if typeof(ex_i) == Expr
      head_i = ex_i.head  # function
      # each ex_i has 2 args, a function signature and a function body
      println("head_i = ", head_i)

      # figure out what kind of expression it is, do the right modification
      if head_i == :function
        rewrite_sig(ex_i.args[1])
        rewrite_body(ex_i.args[2])
      elseif ex_i.head == :const
        make_global_const(ex_i)
      elseif ex_i.head == :typealias
        fix_typealias(ex_i)
      else
        println("not processing expression", ex_i)
      end

    else
      println("not processing ", typeof(ex_i))
    end  # end if Expr


  end

  return obuf  # return modified obuf
end


##### functions to rewrite function signature #####
function rewrite_sig(ex)  # rewrite the function signature

  @assert ex.head == :call  # verify this is a function signature expression

  # ex.args[1] = function name, as a symbol

   # check if function contains a PetscScalar

   # if yes, add paramterization, do search and replace PetscScalar -> S
   # also add macro

   println("rewrite_sig ex = ", ex)
   val = contains_symbol(ex, :PetscScalar)
   println("contains_symbol = ", val)


  for i=2:length(ex.args)  # process all arguments of the function,
                           # each of which is an expression containing arg name, argtype
    println("typeof(ex.args[$i]) = ", typeof(ex.args[i]))
    @assert typeof(ex.args[i]) == Expr  || typeof(ex.args[i]) == Symbol  # verify these are all expressions
    process_sig_arg(ex.args[i])  # process each expression
  end

  for i=2:length(ex.args)  # do second pass to replace PetscScalar with proper type
    for j in keys(type_dict)  # check for all types

    println("replacing ", j, ", with ", type_dict[j])
      replace_symbol(ex.args[i], j, type_dict[j])
    end
  end

  println("after modification rewrite_sig ex = ", ex)
end

function process_sig_arg(ex)  # take the expression that is an argument to the function and rewrite it

   @assert ex.head == :(::)
   
   # modify args here
#   arg_name = ex.args[1]  # symbol
#   arg_type = ex.args[2]  # Expr contianing type tag
   println("ex.args[2] = ", ex.args[2])
   println("type = ", typeof(ex.args[2]))

#   if typeof(ex.args[1]) == Symbol
     

   ex.args[2] = modify_typetag(ex.args[2])

end

function modify_typetag(ex)

#  @assert ex.head == :curly  # verify this is a typetag
  return get(ptr_dict, ex, ex)  # get new typetag if one was given, either an Expr or a Symbol
end

function add_param(ex)
# add the {S <: PetscScalar} to a function declaration

  @assert typeof(ex) == Symbol  # make sure we don't already have a paramaterization

  # could do more extensive operations here
  return :($ex{S <: PetscScalars})
end
  


#####  function to  rewrite the body of the function #####
function rewrite_body(ex)  # rewrite body of a function


  @assert ex.head == :block
  # ex has only one argument, the ccall
  # could insert other statements arond the ccall here?

  process_ccall(ex.args[1])
end


function process_ccall(ex)

  @assert ex.head == :ccall  # verify this is the ccall statement
  # args[1] = Expr, tuple of fname, libname
  # args[2] = return type, symbol
  # args[3] = Expr, tuple of types to ccall
  # args[4] = symbol, first argument name,
  # ...
  modify_types(ex.args[3])

end

function modify_types(ex)

  @assert ex.head == :tuple

  for i=1:length(ex.args)
    ex.args[i] = get(ccall_dict, ex.args[i], ex.args[i])  # get the new argument type symbol from dictionary
  end                                                      # use existing type of no key found

  return nothing
end
   
    
##### functions to make consts into global consts #####

function make_global_const(ex)

  @assert ex.head == :const
 
  val = ex.args[1]  # get the assignment
  ex.args[1] = :(global $val)  # make it global

end


function fix_typealias(ex)

  @assert ex.head == :typealias

  if typeof(ex.args[2]) == Expr  # this a compound type declaration
    new_type = ex.args[1]
    if haskey(type_dict, new_type)
      return "# no typealias $ex"
    end
#=
    ex2 = ex.args[2]
    @assert ex2.head == :curly
    str = string(ex2.args[2])  # get the pointee type name
    println("str = ", str)
    println("str[1] = ", str[1])
    if str[1] == '_'  # if it begin with an underscore
      println("rewriting typealias")
      ex2.args[2] = :Void  # make it a Ptr{Void}
      println("ex2 = ", ex2)
      println("ex = ", ex)
    end
    # else do nothing
=#
  end
end



##### Misc. functions ####

function contains_symbol(ex, sym::Symbol)
# do a recursive check to see if the expression ex contains a symbol

  @assert typeof(ex) == Expr

  sum = 0  

  if ex.head == :(::)  # if this expression is a type annotation
    for i=1:length(ex.args)
      if typeof(ex.args[i]) == Expr
        sum += check_annot(ex.args[i], sym)
        
      else  # this is a symbol
#        println("    comparing ", ex.args[i], " to ", sym)
        if ex.args[i] == sym
#          println("comparison true")
         return true
        end
#        println("comparison false")
     end  # end if ... else
    end  # end for

  else  # keep recursing

    for i=1:length(ex.args)
      if typeof(ex.args[i]) == Expr
#        println("  processing sub expression ", ex.args[i])
        sum += contains_symbol(ex.args[i], sym)
#        println("  sum = ", sum)
      end  # else let this expression fall out of loop
    end  # end loop over args

  end  # end if ... else

  return sum

end

function check_annot(ex, sym::Symbol)
# check a type annotation

  for i=1:length(ex.args)
#   println("  comparing ", ex.args[i], ", to ", sym)
   if ex.args[i] == sym
#    println("  comparison true")
    return true
   end
#   println("  comparsion false")
  end

  return false
end


function replace_symbol(ex, sym_old::Symbol, sym_new::Symbol)
# do a recursive descent replace one symbol with another

#  @assert typeof(ex) == Expr
  println("receiving expression ", ex)

  if typeof(ex) == Symbol  # if this is a symbol
      println("  found symbol ", ex)
      if ex == sym_old
        println("  performing replacement ", ex, " with ", sym_new)
        return sym_new
      else
        println("  returning original symbol")
        return ex
      end
        
  elseif typeof(ex)  == Expr  # keep recursing
  
    for i=1:length(ex.args)
#        println("  processing sub expression ", ex.args[i])
         println("  recursing expression ", ex.args[i]) 
         ex.args[i] =  replace_symbol(ex.args[i], sym_old, sym_new)
    end  # end loop over args
  else # we don't know/care what this expression is
    println("  not modify unknown expression ", ex)
    return ex
  end  # end if ... elseifa

  println("Warning, got to end of replace_symbol")
  println("ex = ", ex)
  println("typeof(ex) = ", typeof(ex))

  return ex

end


