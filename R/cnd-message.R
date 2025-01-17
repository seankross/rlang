#' Build an error message from parts
#'
#' @description
#'
#' `cnd_message()` assembles an error message from three generics:
#'
#' - `cnd_header()`
#' - `cnd_body()`
#' - `cnd_footer()`
#'
#' Methods for these generics must return a character vector. The
#' elements are combined into a single string with a newline
#' separator. Bullets syntax is supported, either through rlang (see
#' [format_error_bullets()]), or through cli if the condition has
#' `use_cli_format` set to `TRUE`.
#'
#' The default method for the error header returns the `message` field
#' of the condition object. The default methods for the body and
#' footer return the the `body` and `footer` fields if any, or empty
#' character vectors otherwise.
#'
#' `cnd_message()` is automatically called by the `conditionMessage()`
#' for rlang errors, warnings, and messages. Error classes created
#' with [abort()] only need to implement header, body or footer
#' methods. This provides a lot of flexibility for hierarchies of
#' error classes, for instance you could inherit the body of an error
#' message from a parent class while overriding the header and footer.
#'
#'
#' @section Overriding `cnd_body()`:
#'
#' `r lifecycle::badge("experimental")`
#'
#' Sometimes the contents of an error message depends on the state of
#' your checking routine. In that case, it can be tricky to lazily
#' generate error messages with `cnd_body()`: you have the choice
#' between overspecifying your error class hierarchies with one class
#' per state, or replicating the type-checking control flow within the
#' `cnd_body()` method. None of these options are ideal.
#'
#' A better option is to define a `body` field in your error object
#' containing a static string, a [lambda-formula][as_function], or a
#' function with the same signature as `cnd_body()`. This field
#' overrides the `cnd_body()` generic and makes it easy to generate an
#' error message tailored to the state in which the error was
#' constructed.
#'
#' @param cnd A condition object.
#' @param ... Arguments passed to methods.
#'
#' @export
cnd_message <- function(cnd) {
  cnd_format <- cnd_formatter(cnd)
  cnd_format(cnd_message_lines(cnd))
}
cnd_message_lines <- function(cnd) {
  c(
    cnd_header(cnd),
    cnd_body(cnd),
    cnd_footer(cnd)
  )
}

cnd_formatter <- function(cnd) {
  if (!is_true(cnd$use_cli_format)) {
    return(function(x, indent = FALSE) {
      x <- paste_line(x)
      if (indent) {
        x <- paste0("  ", x)
        x <- gsub("\n", "\n  ", x, fixed = TRUE)
      }
      x
    })
  }

  # FIXME! Use `format_message()` instead of `format_error()` until
  # https://github.com/r-lib/cli/issues/345 is fixed
  cli_format <- switch(
    cnd_type(cnd),
    error = cli::format_message,
    warning = cli::format_warning,
    cli::format_message
  )

  function(x, indent = FALSE) {
    if (indent) {
      local_cli_indent()
    }
    cli_format(glue_escape(x), .envir = emptyenv())
  }
}

local_cli_indent <- function(frame = caller_env()) {
  cli::cli_div(
    class = "indented",
    theme = list(div.indented = list("margin-left" = 2)),
    .envir = frame
  )
}

#' @rdname cnd_message
#' @export
cnd_header <- function(cnd, ...) {
  UseMethod("cnd_header")
}
#' @export
cnd_header.default <- function(cnd, ...) {
  cnd$message
}

#' @rdname cnd_message
#' @export
cnd_body <- function(cnd, ...) {
  if (is_null(cnd$body)) {
    UseMethod("cnd_body")
  } else {
    override_cnd_body(cnd, ...)
  }
}
#' @export
cnd_body.default <- function(cnd, ...) {
  chr()
}

override_cnd_body <- function(cnd, ...) {
  body <- cnd$body

  if (is_function(body)) {
    body(cnd, ...)
  } else if (is_bare_formula(body)) {
    body <- as_function(body)
    body(cnd, ...)
  } else if (is_character(body)) {
    body
  } else {
    abort("`body` must be a string or a function.")
  }
}

#' @rdname cnd_message
#' @export
cnd_footer <- function(cnd, ...) {
  UseMethod("cnd_footer")
}
#' @export
cnd_footer.default <- function(cnd, ...) {
  cnd$footer %||% chr()
}

cnd_build_error_message <- function(cnd) {
  msg <- cnd_prefixed_message(cnd, parent = FALSE)

  while (is_error(cnd <- cnd$parent)) {
    parent_msg <- cnd_prefixed_message(cnd, parent = TRUE)
    msg <- paste_line(msg, parent_msg)
  }

  msg
}

cnd_prefixed_message <- function(cnd, parent = FALSE) {
  type <- cnd_type(cnd)

  if (parent) {
    prefix <- sprintf("Caused by %s", type)
    indent <- TRUE
  } else {
    prefix <- col_yellow(capitalise(type))
    indent <- is_condition(cnd$parent)
  }

  if (is_true(cnd$use_cli_format)) {
    if (parent) {
      message <- cnd_header(cnd)
    } else {
      message <- cnd_message_lines(cnd)
    }

    cnd_format <- cnd_formatter(cnd)
    message <- cnd_format(message, indent = indent)
  } else {
    message <- conditionMessage(cnd)
    if (indent) {
      message <- paste0("  ", message)
      message <- gsub("\n", "\n  ", message, fixed = TRUE)
    }
  }

  message <- strip_trailing_newline(message)

  if (!nzchar(message)) {
    return(NULL)
  }

  call <- format_error_call(cnd$call)
  has_loc <- FALSE

  if (is_null(call)) {
    prefix <- sprintf("%s: ", prefix)
  } else {
    src_loc <- src_loc(attr(cnd$call, "srcref"))
    if (nzchar(src_loc) && !is_testing()) {
      prefix <- sprintf("%s in %s at %s: ", prefix, call, src_loc)
      has_loc <- TRUE
    } else {
      prefix <- sprintf("%s in %s: ", prefix, call)
    }
  }
  prefix <- style_bold(prefix)

  break_line <-
    indent ||
    has_loc ||
    nchar(strip_style(prefix)) > (peek_option("width") / 2)

  if (break_line) {
    paste0(prefix, "\n", message)
  } else {
    paste0(prefix, message)
  }
}

#' @export
conditionMessage.rlang_message <- function(c) {
  cnd_message(c)
}
#' @export
conditionMessage.rlang_warning <- function(c) {
  cnd_message(c)
}
#' @export
conditionMessage.rlang_error <- function(c) {
  cnd_message(c)
}


#' Format bullets for error messages
#'
#' @description
#' `format_error_bullets()` takes a character vector and returns a single
#' string (or an empty vector if the input is empty). The elements of
#' the input vector are assembled as a list of bullets, depending on
#' their names:
#'
#' - Unnamed elements are unindented. They act as titles or subtitles.
#' - Elements named `"*"` are bulleted with a cyan "bullet" symbol.
#' - Elements named `"i"` are bulleted with a blue "info" symbol.
#' - Elements named `"x"` are bulleted with a red "cross" symbol.
#' - Elements named `"v"` are bulleted with a green "tick" symbol.
#' - Elements named `"!"` are bulleted with a yellow "warning" symbol.
#' - Elements named `">"` are bulleted with an "arrow" symbol.
#' - Elements named `" "` start with an indented line break.
#'
#' For convenience, if the vector is fully unnamed, the elements are
#' formatted as "*" bullets.
#'
#' The bullet formatting for errors follows the idea that sentences in
#' error messages are best kept short and simple. The best way to
#' present the information is in the [cnd_body()] method of an error
#' conditon as a bullet list of simple sentences containing a single
#' clause. The info and cross symbols of the bullets provide hints on
#' how to interpret the bullet relative to the general error issue,
#' which should be supplied as [cnd_header()].
#'
#' @param x A named character vector of messages. Named elements are
#'   prefixed with the corresponding bullet. Elements named with a
#'   single space `" "` trigger a line break from the previous bullet.
#' @examples
#' # All bullets
#' writeLines(format_error_bullets(c("foo", "bar")))
#'
#' # This is equivalent to
#' writeLines(format_error_bullets(set_names(c("foo", "bar"), "*")))
#'
#' # Supply named elements to format info, cross, and tick bullets
#' writeLines(format_error_bullets(c(i = "foo", x = "bar", v = "baz", "*" = "quux")))
#'
#' # An unnamed element breaks the line
#' writeLines(format_error_bullets(c(i = "foo\nbar")))
#'
#' # A " " element breaks the line within a bullet (with indentation)
#' writeLines(format_error_bullets(c(i = "foo", " " = "bar")))
#' @export
format_error_bullets <- function(x) {
  # Treat unnamed vectors as all bullets
  if (is_null(names(x))) {
    x <- set_names(x, "*")
  }

  # Always use fallback for now
  .rlang_cli_format_fallback(x)
}

# FIXME: These won't be needed after warnings and messages have been
# switched to print-time formatting
rlang_format_warning <- function(x, env = caller_env()) {
  rlang_format(x, env, format_warning, cli::format_warning)
}
rlang_format_message <- function(x, env = caller_env()) {
  rlang_format(x, env, format_message, cli::format_message)
}
rlang_format <- function(x, env, partial_format, cli_format) {
  if (!can_format(x)) {
    return(x)
  }

  use_cli <- use_cli(env)
  inline <- use_cli[["inline"]]
  format <- use_cli[["format"]]

  # Full
  if (inline && format) {
    return(.rlang_cli_str_restore(cli_format(x, env), x))
  }

  # Partial
  if (format) {
    if (has_cli_format) {
      return(partial_format(cli_escape(x)))
    } else {
      return(.rlang_cli_format_fallback(x))
    }
  }

  # None
  x
}

# No-op for the empty string, e.g. for `abort("", class = "foo")` and
# a `conditionMessage.foo()` method. Don't format inputs escaped with `I()`.
can_format <- function(x) {
  !is_string(x, "") && !inherits(x, "AsIs")
}
