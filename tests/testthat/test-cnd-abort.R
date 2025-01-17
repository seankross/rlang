test_that("errors are signalled with backtrace", {
  fn <- function() abort("")
  err <- expect_error(fn())
  expect_s3_class(err$trace, "rlang_trace")
})

test_that("can pass classed strings as error message", {
  message <- structure("foo", class = c("glue", "character"))
  err <- expect_error(abort(message))
  expect_identical(err$message, message)
})

test_that("errors are saved", {
  # `outFile` argument
  skip_if(getRversion() < "3.4")

  file <- tempfile()
  on.exit(unlink(file))

  # Verbose try() triggers conditionMessage() and thus saves the error.
  # This simulates an unhandled error.
  local_options(
    `rlang::::force_unhandled_error` = TRUE,
    `rlang:::message_file` = tempfile()
  )

  try(abort("foo", "bar"), outFile = file)
  expect_true(inherits_all(last_error(), c("bar", "rlang_error")))

  try(cnd_signal(error_cnd("foobar")), outFile = file)
  expect_true(inherits_all(last_error(), c("foobar", "rlang_error")))
})

test_that("No backtrace is displayed with top-level active bindings", {
  local_options(
    rlang_trace_top_env = current_env()
  )

  env_bind_active(current_env(), foo = function() abort("msg"))
  expect_error(foo, "^msg$")
})

test_that("Invalid on_error option resets itself", {
  with_options(
    `rlang::::force_unhandled_error` = TRUE,
    `rlang:::message_file` = tempfile(),
    rlang_backtrace_on_error = NA,
    {
      expect_warning(tryCatch(abort("foo"), error = identity), "Invalid")
      expect_null(peek_option("rlang_backtrace_on_error"))
    }
  )
})

test_that("format_onerror_backtrace handles empty and size 1 traces", {
  local_options(rlang_backtrace_on_error = "branch")

  trace <- new_trace(list(), int())
  expect_identical(format_onerror_backtrace(trace), NULL)

  trace <- new_trace(list(quote(foo)), int(0))
  expect_identical(format_onerror_backtrace(trace), NULL)

  trace <- new_trace(list(quote(foo), quote(bar)), int(0, 1))
  expect_match(format_onerror_backtrace(error_cnd(trace = trace)), "foo.*bar")
})

test_that("error is printed with backtrace", {
  skip_if_stale_backtrace()

  run_error_script <- function(envvars = chr()) {
    run_script(test_path("fixtures", "error-backtrace.R"), envvars = envvars)
  }

  default_interactive <- run_error_script(envvars = "rlang_interactive=true")
  default_non_interactive <- run_error_script()
  reminder <- run_error_script(envvars = "rlang_backtrace_on_error=reminder")
  branch <- run_error_script(envvars = "rlang_backtrace_on_error=branch")
  collapse <- run_error_script(envvars = "rlang_backtrace_on_error=collapse")
  full <- run_error_script(envvars = "rlang_backtrace_on_error=full")

  rethrown_interactive <- run_script(
    test_path("fixtures", "error-backtrace-rethrown.R"),
    envvars = "rlang_interactive=true"
  )
  rethrown_non_interactive <- run_script(
    test_path("fixtures", "error-backtrace-rethrown.R")
  )

  expect_snapshot({
    cat_line(default_interactive)
    cat_line(default_non_interactive)
    cat_line(reminder)
    cat_line(branch)
    cat_line(collapse)
    cat_line(full)
    cat_line(rethrown_interactive)
    cat_line(rethrown_non_interactive)
  })
})

test_that("empty backtraces are not printed", {
  skip_if_stale_backtrace()

  run_error_script <- function(envvars = chr()) {
    run_script(test_path("fixtures", "error-backtrace-empty.R"), envvars = envvars)
  }

  branch_depth_0 <- run_error_script(envvars = c("rlang_backtrace_on_error=branch", "trace_depth=0"))
  full_depth_0 <- run_error_script(envvars = c("rlang_backtrace_on_error=full", "trace_depth=0"))
  branch_depth_1 <- run_error_script(envvars = c("rlang_backtrace_on_error=branch", "trace_depth=1"))
  full_depth_1 <- run_error_script(envvars = c("rlang_backtrace_on_error=full", "trace_depth=1"))

  expect_snapshot({
    cat_line(branch_depth_0)
    cat_line(full_depth_0)
    cat_line(branch_depth_1)
    cat_line(full_depth_1)
  })
})

test_that("parent errors are not displayed in error message and backtrace", {
  skip_if_stale_backtrace()

  run_error_script <- function(envvars = chr()) {
    run_script(
      test_path("fixtures", "error-backtrace-parent.R"),
      envvars = envvars
    )
  }
  non_interactive <- run_error_script()
  interactive <- run_error_script(envvars = "rlang_interactive=true")

  expect_snapshot({
    cat_line(interactive)
    cat_line(non_interactive)
  })
})

test_that("backtrace reminder is displayed when called from `last_error()`", {
  local_options(
    rlang_trace_format_srcrefs = FALSE,
    rlang_trace_top_env = current_env()
  )

  f <- function() g()
  g <- function() h()
  h <- function() abort("foo")
  err <- catch_error(f())

  poke_last_error(err)

  expect_snapshot({
    "Normal case"
    print(err)

    "From `last_error()`"
    print(last_error())

    "Saved from `last_error()`"
    {
      saved <- last_error()
      print(saved)
    }

    "Saved from `last_error()`, but no longer last"
    {
      poke_last_error(error_cnd("foo"))
      print(saved)
    }
  })
})

test_that("capture context doesn't leak into low-level backtraces", {
  local_options(
    rlang_trace_format_srcrefs = FALSE,
    rlang_trace_top_env = current_env()
  )

  failing <- function() stop("low-level")
  stop_wrapper <- function(...) abort("wrapper", ...)
  f <- function() g()
  g <- function() h()
  h <- function() {
    tryCatch(
      failing(),
      error = function(err) {
        if (wrapper) {
          stop_wrapper(parent = err)
        } else {
          if (parent) {
            abort("no wrapper", parent = err)
          } else {
            abort("no wrapper")
          }
        }
      }
    )
  }

  foo <- function(cnd) bar(cnd)
  bar <- function(cnd) baz(cnd)
  baz <- function(cnd) abort("foo")
  err_wch <- catch_error(
    withCallingHandlers(
      foo(),
      error = function(cnd) abort("bar", parent = cnd)
    )
  )

  expect_snapshot({
    "Non wrapped case"
    {
      parent <- TRUE
      wrapper <- FALSE
      err <- catch_error(f())
      print(err)
    }

    "Wrapped case"
    {
      wrapper <- TRUE
      err <- catch_error(f())
      print(err)
    }

    "FIXME?"
    {
      parent <- FALSE
      err <- catch_error(f())
      print(err)
    }

    "withCallingHandlers()"
    print(err_wch)
  })
})

test_that("`.subclass` argument of `abort()` still works", {
  expect_error(abort("foo", .subclass = "bar"), class = "bar")
})

test_that("abort() displays call in error prefix", {
  skip_if_not_installed("rlang", "0.4.11.9001")

  expect_snapshot(
    run("rlang::abort('foo', call = quote(bar(baz)))")
  )

  # errorCondition()
  skip_if_not_installed("base", "3.6.0")

  expect_snapshot(
    run("rlang::cnd_signal(errorCondition('foo', call = quote(bar(baz))))")
  )
})

test_that("abort() accepts environment as `call` field.", {
  arg_require2 <- function(arg, error_call = caller_call()) {
    arg_require(arg, error_call = error_call)
  }
  f <- function(x) g(x)
  g <- function(x) h(x)
  h <- function(x) arg_require2(x, error_call = environment())

  expect_snapshot((expect_error(f())))
})

test_that("format_error_arg() formats argument", {
  exp <- format_arg("foo")

  expect_equal(format_error_arg("foo"), exp)
  expect_equal(format_error_arg(sym("foo")), exp)
  expect_equal(format_error_arg(chr_get("foo", 0L)), exp)
  expect_equal(format_error_arg(quote(foo())), format_arg("foo()"))

  expect_error(format_error_arg(c("foo", "bar")), "must be a string or an expression")
  expect_error(format_error_arg(function() NULL), "must be a string or an expression")
})

test_that("local_error_call() works", {
  foo <- function() {
    bar()
  }
  bar <- function() {
    local_error_call(quote(expected()))
    baz()
  }
  baz <- function() {
    local_error_call("caller")
    abort("tilt")
  }

  expect_snapshot((expect_error(foo())))
})

test_that("can disable error call inference for unexported functions", {
  foo <- function() abort("foo")

  expect_snapshot({
    (expect_error(foo()))

    local({
      local_options("rlang:::restrict_default_error_call" = TRUE)
      (expect_error(foo()))
    })

    local({
      local_options("rlang:::restrict_default_error_call" = TRUE)
      (expect_error(dots_list(.homonyms = "k")))
    })
  })
})

test_that("error call flag is stripped", {
  e <- env(.__error_call__. = quote(foo(bar)))
  expect_equal(error_call(e), quote(foo(bar)))
  expect_equal(format_error_call(e), "`foo()`")
})

test_that("NSE doesn't interfere with error call contexts", {
  # Snapshots shouldn't show `eval()` as context
  expect_snapshot({
    (expect_error(local(arg_match0("f", "foo"))))
    (expect_error(eval_bare(quote(arg_match0("f", "foo")))))
    (expect_error(eval_bare(quote(arg_match0("f", "foo")), env())))
  })
})

test_that("error_call() requires a symbol in function position", {
  expect_null(format_error_call(quote(foo$bar())))
  expect_null(format_error_call(quote((function() NULL)())))
  expect_null(format_error_call(call2(function() NULL)))
})

test_that("error_call() preserves `if` (r-lib/testthat#1429)", {
  call <- quote(if (foobar) TRUE else FALSE)

  expect_equal(
    error_call(call),
    call
  )
  expect_equal(
    format_error_call(call),
    "`if (foobar) ...`"
  )
})

test_that("error_call() and format_error_call() preserve special syntax ops", {
  expect_equal(
    error_call(quote(1 + 2)),
    quote(1 + 2)
  )
  expect_equal(
    format_error_call(quote(1 + 2)),
    "`+`"
  )

  expect_equal(
    error_call(quote(for (x in y) NULL)),
    quote(for (x in y) NULL)
  )
  expect_equal(
    format_error_call(quote(for (x in y) NULL)),
    "`for`"
  )

  expect_equal(
    format_error_call(quote(a %||% b)),
    "`%||%`"
  )
  expect_equal(
    format_error_call(quote(`%||%`())),
    "`%||%`"
  )
})

test_that("error_call() preserves srcrefs", {
  eval_parse("{
    f <- function() g()
    g <- function() h()
    h <- function() abort('Foo.')
  }")

  out <- error_call(catch_error(f())$call)
  expect_s3_class(attr(out, "srcref"), "srcref")
})

test_that("withCallingHandlers() wrappers don't throw off trace capture on rethrow", {
  local_options(
    rlang_trace_top_env = current_env(),
    rlang_trace_format_srcrefs = FALSE
  )

  f <- function() g()
  g <- function() h()
  h <- function() abort("Low-level message")

  wch <- function(expr, ...) withCallingHandlers(expr, ...)
  wrapper1 <- function(err) wrapper2(err)
  wrapper2 <- function(err) abort("High-level message", parent = err)

  foo <- function() bar()
  bar <- function() baz()
  baz <- function() {
    wch(
      f(),
      error = function(err) {
        wrapper1(err)
      }
    )
  }

  err <- expect_error(foo())
  expect_snapshot({
    "`abort()` error"
    print(err)
    summary(err)
  })

  # Avoid `:::` vs `::` ambiguity depending on loadall
  fail <- errorcall
  h <- function() fail(NULL, "foo")
  err <- expect_error(foo())
  expect_snapshot({
    "C-level error"
    print(err)
    summary(err)
  })
})

test_that("headers and body are stored in respective fields", {
  local_use_cli()  # Just to be explicit

  cnd <- catch_cnd(abort(c("a", "b", i = "c")), "error")
  expect_equal(cnd$message, set_names("a", ""))
  expect_equal(cnd$body, c("b", i = "c"))
})

test_that("`abort()` uses older bullets formatting by default", {
  local_use_cli(format = FALSE)
  expect_snapshot_error(abort(c("foo", "bar")))
})

test_that("abort() preserves `call`", {
  err <- catch_cnd(abort("foo", call = quote(1 + 2)), "error")
  expect_equal(err$call, quote(1 + 2))
})

test_that("format_error_call() preserves I() inputs", {
  expect_equal(
    format_error_call(I(quote(.data[[1]]))),
    "`.data[[1]]`"
  )
})

test_that("format_error_call() detects non-syntactic names", {
  expect_equal(
    format_error_call(quote(`[[.foo`())),
    "`[[.foo`"
  )
})

test_that("generic call is picked up in methods", {  
  g <- function(call = caller_env()) {
    abort("foo", call = call)
  }

  f1 <- function(x) {
    UseMethod("f1")
  }
  f1.default <- function(x) {
    g()
  }

  f2 <- function(x) {
    UseMethod("f2")
  }
  f2.NULL <- function(x) {
    NextMethod()
  }
  f2.default <- function(x) {
    g()
  }

  f3 <- function(x) {
    UseMethod("f3")
  }
  f3.foo <- function(x) {
    NextMethod()
  }
  f3.bar <- function(x) {
    NextMethod()
  }
  f3.default <- function(x) {
    g()
  }

  f4 <- function(x) {
    f4_dispatch(x)
  }
  f4_dispatch <- function(x) {
    local_error_call("caller")
    UseMethod("f4")
  }
  f4.foo <- function(x) {
    NextMethod()
  }
  f4.bar <- function(x) {
    NextMethod()
  }
  f4.default <- function(x) {
    g()
  }

  expect_snapshot({
    err(f1())
    err(f2())
    err(f3())
    err(f4(NULL))
  })
})
