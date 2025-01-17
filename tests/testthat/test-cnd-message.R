test_that("format_error_bullets() formats bullets depending on names", {
  expect_identical(format_error_bullets(c("foo", "bar")), "* foo\n* bar")
  expect_identical(format_error_bullets(c(i = "foo", "*" = "baz", x = "bar", v = "bam")), "i foo\n* baz\nx bar\nv bam")
  expect_error(format_error_bullets(c(i = "foo", u = "bar")))
  expect_identical(format_error_bullets(chr()), chr())
})

test_that("default conditionMessage() method for rlang errors calls cnd_message()", {
  # Fallback
  out <- conditionMessage(error_cnd("rlang_foobar", message = "embedded"))
  expect_identical(out, "embedded")

  # Only `cnd_header()` method
  out <- with_methods(
    cnd_header.rlang_foobar = function(cnd, ...) "dispatched!",
    conditionMessage(error_cnd("rlang_foobar", message = "embedded"))
  )
  expect_identical(out, "dispatched!")

  # Both `cnd_header()` and `cnd_body()` methods
  out <- with_methods(
    cnd_header.rlang_foobar = function(cnd, ...) "dispatched!",
    cnd_body.rlang_foobar = function(cnd, ...) c("one", "two", "three"),
    conditionMessage(error_cnd("rlang_foobar", message = "embedded"))
  )
  exp <- paste0("dispatched!\n", paste_line(c("one", "two", "three")))
  expect_identical(out, exp)

  # All three methods defined
  out <- with_methods(
    cnd_header.rlang_foobar = function(cnd, ...) "dispatched!",
    cnd_body.rlang_foobar = function(cnd, ...) c("one", "two", "three"),
    cnd_footer.rlang_foobar = function(cnd, ...) c("foo", "bar"),
    conditionMessage(error_cnd("rlang_foobar", message = "embedded"))
  )
  exp <- paste0(exp, "\nfoo\nbar")
  expect_identical(out, exp)
})

test_that("can override body method with `body` fields", {
  local_methods(cnd_body.rlang_foobar = function(...) "wrong")

  expect_error(
    stop(error_cnd("rlang_foobar", message = "header", body = "body")),
    "header\nbody",
    class = "rlang_foobar"
  )
  expect_error(
    stop(error_cnd("rlang_foobar", message = "header", body = ~ "body")),
    "header\nbody",
    class = "rlang_foobar"
  )
  expect_error(
    stop(error_cnd("rlang_foobar", message = "header", body = function(...) "body")),
    "header\nbody",
    class = "rlang_foobar"
  )

  expect_error(
    stop(error_cnd("rlang_foobar", message = "header", body = ~ format_error_bullets("body"))),
    "header\n* body",
    fixed = TRUE,
    class = "rlang_foobar"
  )
})

test_that("`body` must be a character vector or a function", {
  expect_error(
    stop(error_cnd("foo", body = 1:3)),
    "must be a string or a function"
  )
})

test_that("can request a line break in error bullets (#1130)", {
  expect_snapshot({
    (expect_error(abort(c(
      "Main header.",
      "Header 1",
      x = "Bullet 1",
      x = "Bullet 2",
      "Header 2",
      x = "Bullet 3",
      x = "Bullet 4"
    ))))

    (expect_error(abort(c(
      "Main header.",
      "Header 1",
      "x" = "Bullet 1",
      " " = "Break line",
      "x" = "Bullet 2",
      "",
      "Header 2",
      "x" = "Bullet 3",
      " " = "Break line",
      "x" = "Bullet 4"
    ))))
  })
})

test_that("fully unnamed bullet vectors are treated as bullets", {
  expect_equal(
    format_error_bullets("foo"),
    "* foo"
  )
  expect_equal(
    format_error_bullets(c("foo", "bar")),
    "* foo\n* bar"
  )

  non_bullets <- set_names(c("foo", "bar"), c("", ""))
  expect_equal(
    format_error_bullets(non_bullets),
    "foo\nbar"
  )
})

test_that("empty names in partially named bullet vectors are treated as line breaks", {
  expect_equal(
    format_error_bullets(c("foo", i = "bar", "baz")),
    "foo\ni bar\nbaz"
  )
  expect_equal(
    format_error_bullets(c(i = "bar", "baz")),
    "i bar\nbaz"
  )
})

test_that("! and > symbols create warning and alert bullets", {
  expect_equal(
    format_error_bullets(c("Header", "!" = "Attention", ">" = "Alert")),
    "Header\n! Attention\n> Alert"
  )
})

test_that("cli is not used when message is escaped with `I()`", {
  local_use_cli(inline = TRUE)

  x <- "foo"

  expect_equal(
    conditionMessage(expect_error(abort("{x}"))),
    "foo"
  )

  return("no longer the case")

  expect_equal(
    conditionMessage(expect_error(abort(I("{x}")))),
    "{x}"
  )
})

test_that("cli syntax is escaped in 'try' mode", {
  local_use_cli()

  x <- "{foo {{}}"
  expect_equal(rlang_format_message(x), x)
})

test_that(".rlang_cli_str_restore() deals with attributes", {
  msg <- structure("foo", attr = TRUE)

  expect_equal(
    .rlang_cli_str_restore("bar", msg),
    structure("bar", attr = TRUE)
  )

  msg_oo <- structure("foo", attr = TRUE, class = "foo")
  expect_equal(
    .rlang_cli_str_restore("bar", msg_oo),
    "bar"
  )

  local_use_cli(inline = TRUE, format = TRUE)
  expect_equal(
    attributes(rlang_format_message(msg)),
    list(attr = TRUE)
  )

  local_use_cli(inline = FALSE, format = FALSE)
  expect_equal(
    attributes(rlang_format_message(msg)),
    list(attr = TRUE)
  )

  local_use_cli(inline = FALSE, format = TRUE)
  expect_equal(
    attributes(rlang_format_message(msg)),
    list(attr = TRUE)
  )
})

skip_if_not_installed("cli", "2.5.0")
skip_if_not_installed("glue")

cli::test_that_cli("format_error_bullets() generates bullets", {
  expect_snapshot({
    format_error_bullets(c("Header.", i = "Bullet."))
  })
})

cli::test_that_cli(configs = c("plain", "fancy"), "can use cli syntax in `cnd_message()` methods", {
  local_methods(
    cnd_header.rlang_foobar = function(cnd, ...) {
      cli::format_error("Header: {.emph {cnd$field}}")
    },
    cnd_body.rlang_foobar = function(cnd, ...) {
      cli::format_error(c("i" = "Bullet: {.emph {cnd$field}}"))
    },
    cnd_footer.rlang_foobar = function(cnd, ...) {
      cli::format_error(c("_" = "Footer: {.emph {cnd$field}}"))
    }
  )
  cnd <- error_cnd(
    "rlang_foobar",
    field = "User { {field}."
  )
  expect_snapshot(cnd_message(cnd))
})

test_that("prefix takes call into account", {
  err <- error_cnd(message = "msg", call = quote(foo(bar = TRUE)))
  expect_equal(cnd_prefixed_message(err), "Error in `foo()`: msg")

  # Inlined objects disable context deparsing
  err1 <- error_cnd(message = "msg", call = expr(foo(bar = !!(1:3))))
  err2 <- error_cnd(message = "msg", call = quote(foo$bar()))
  err3 <- error_cnd(message = "msg", call = call2(identity))
  expect_equal(cnd_prefixed_message(err1), "Error in `foo()`: msg")
  expect_equal(cnd_prefixed_message(err2), "Error: msg")
  expect_equal(cnd_prefixed_message(err3), "Error: msg")
})

test_that("long prefixes cause a line break", {
  very_very_very_very_very_long_function_name <- function() {
    abort("My somewhat longish and verbose error message.")
  }

  expect_snapshot((expect_error(very_very_very_very_very_long_function_name())))
})

test_that("prefixes include srcrefs", {
  withr::local_envvar("TESTTHAT" = "")

  eval_parse("{
    f <- function() g()
    g <- function() abort('Foo.')
  }")

  src_file <- g %@% srcref %@% srcfile
  src_file$filename <- "/foo/bar/baz/myfile.R"

  expect_snapshot((expect_error(f())))
})

test_that("inform() and warn() use fallback bullets formatting", {
  msg <- c("foo", i = "bar")

  expect_snapshot({
    local_use_cli(format = FALSE)
    warn(msg)
    warn(msg, .frequency = "once", .frequency_id = as.character(runif(1)))
  })

  expect_snapshot({
    local_use_cli(format = TRUE)
    warn(msg)
    warn(msg, .frequency = "once", .frequency_id = as.character(runif(1)))
  })

  expect_snapshot({
    local_use_cli(format = FALSE)
    inform(msg)
    inform(msg, .frequency = "once", .frequency_id = as.character(runif(1)))
  })

  expect_snapshot({
    local_use_cli(format = TRUE)
    inform(msg)
    inform(msg, .frequency = "once", .frequency_id = as.character(runif(1)))
  })
})

test_that("cnd_message() uses `body` and `footer` fields by default", {
  expect_equal(
    cnd_message(cnd("foo", message = "foo", footer = "baz")),
    "foo\nbaz"
  )
  expect_equal(
    cnd_message(cnd("foo", message = "foo", body = "bar", footer = "baz")),
    "foo\nbar\nbaz"
  )
})

test_that("can supply bullet without header", {
  expect_snapshot({
    (catch_cnd(inform(c(i = "foo")), "message"))
    (catch_cnd(warn(c(i = "foo")), "warning"))
  })
})
