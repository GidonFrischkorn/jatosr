# CRAN policy rules that R CMD check does not enforce.
#
# CRAN's reviewers read every new submission by hand and send back comments
# on patterns that `R CMD check --as-cran` passes without a note: a triple
# colon on a help page, examples for unexported functions, a missing \value,
# T and F for TRUE and FALSE, a function that changes options() without
# on.exit(). Each rule below is one such comment, with the place it is
# documented, turned into a static check over the package sources. Rules that
# R CMD check itself enforces (title case, a Description that starts with
# "This package", DOI and URL formats, a triple colon in R code) are left to
# it.
#
# Portable by design: copy this one file into tests/testthat/ of any R
# package. It needs base R, tools, utils and testthat, reads the package name
# from DESCRIPTION, and defines nothing outside the `cran_policy_` prefix.
# Only the settings block below is meant to change between repositories.
#
# Exceptions. A comment `cran-policy: allow <rule-id> <reason>` on a line
# exempts that line from that rule: in R code, tests, vignette chunks, and in
# example code, whose comments reach the Rd files. Rules about a whole help
# page or about DESCRIPTION take exceptions in `cran_policy_settings$allow`.
#
# The checks need the package sources. Under R CMD check, and so on CRAN, the
# tests run from <pkg>.Rcheck/, which has neither DESCRIPTION nor R/, and the
# check against the package reports a skip rather than passing over nothing.
# The self-tests on a generated package need no sources but are skipped on
# CRAN: a development check must never fail a CRAN check run.

# Settings --------------------------------------------------------------------

cran_policy_settings <- list(
  # scan tests/ for the triple colon as well as code and documentation
  scan_tests = TRUE,
  # rule id -> exempt keys: file paths relative to the package root for the
  # help-page rules, names or words for the DESCRIPTION rules
  allow = list()
)

# Rules -----------------------------------------------------------------------

cran_policy_cookbook <- "https://contributor.r-project.org/cran-cookbook/"
cran_policy_extrachecks <- "https://github.com/DavisVaughan/extrachecks"

# id -> what the reviewer writes (abridged) and where it is documented
cran_policy_rules <- list(
  "parse" = c(
    "A file that does not parse cannot be checked by the rules below.",
    "(this file)"
  ),
  "triple-colon" = c(
    paste0(
      "Using foo", strrep(":", 3), "f instead of foo::f allows access to ",
      "unexported objects. [...] Please omit one colon."
    ),
    "CRAN incoming review, 2026"
  ),
  "rd-value" = c(
    "Please add \\value to .Rd files regarding exported methods and explain the functions results in the documentation.",
    paste0(cran_policy_cookbook, "docs_issues.html")
  ),
  "rd-examples-unexported" = c(
    "You have examples for unexported functions. Please either omit these examples or export these functions.",
    "https://github.com/NorskRegnesentral/shapr/pull/442"
  ),
  "rd-exported-no-examples" = c(
    "Exported functions are expected to have examples; only side-effect functions are let off.",
    cran_policy_extrachecks
  ),
  "rd-dontrun-reason" = c(
    "\\dontrun{} should only be used if the example really cannot be executed. (Open each block with a comment that says why.)",
    paste0(cran_policy_cookbook, "general_issues.html")
  ),
  "rd-commented-code" = c(
    "Examples/code lines in examples should never be commented out.",
    cran_policy_extrachecks
  ),
  "true-false" = c(
    "Please write TRUE and FALSE instead of T and F.",
    paste0(cran_policy_cookbook, "code_issues.html")
  ),
  "set-seed" = c(
    "Please do not set a seed to a specific number within a function.",
    paste0(cran_policy_cookbook, "code_issues.html")
  ),
  "print-cat" = c(
    "You write information messages to the console that cannot be easily suppressed.",
    paste0(cran_policy_cookbook, "code_issues.html")
  ),
  "reset-state" = c(
    paste(
      "Please make sure that you do not change the user's options, par or working directory.",
      "If you really have to do so within functions, please ensure with an immediate call of on.exit()",
      "that the settings are reset. options(warn = -1) is not allowed at all."
    ),
    paste0(cran_policy_cookbook, "code_issues.html")
  ),
  "global-env" = c(
    "Please do not modify the global environment (e.g., by using <<-) in your functions.",
    paste0(cran_policy_cookbook, "code_issues.html")
  ),
  "installed-packages" = c(
    "You are using installed.packages() in your code. [...] this can be very slow.",
    paste0(cran_policy_cookbook, "code_issues.html")
  ),
  "install-packages" = c(
    "Please do not install packages in your functions, examples or vignettes.",
    paste0(cran_policy_cookbook, "code_issues.html")
  ),
  "cores" = c(
    "Please ensure that you do not use more than 2 cores in your examples, vignettes, etc.",
    paste0(cran_policy_cookbook, "code_issues.html")
  ),
  "home-default" = c(
    "Please ensure that your functions do not write by default [...] in the user's home filespace (including the package directory and getwd()).",
    paste0(cran_policy_cookbook, "code_issues.html")
  ),
  "rm-ls" = c(
    "Please do not modify the user's global environment [...] in your examples or vignettes by deleting objects: rm(list = ls())",
    "https://cran.r-project.org/package=StratifiedSampling/news/news.html"
  ),
  "desc-title" = c(
    "No 'in R' or 'with R' in the Title (every CRAN package is an R package), and at most 65 characters.",
    "https://github.com/ThinkR-open/prepare-for-cran"
  ),
  "desc-description-start" = c(
    "The Description should not start with the Title or with 'Functions for'.",
    cran_policy_extrachecks
  ),
  "desc-quote-packages" = c(
    "Please always write package names, software names and API names in single quotes in title and description.",
    paste0(cran_policy_cookbook, "description_issues.html")
  ),
  "desc-cph" = c(
    "You also seem to be a copyright holder [cph]. Please add this information to the Authors@R field.",
    cran_policy_extrachecks
  ),
  "desc-license-file" = c(
    "We do not need \"+ file LICENSE\" and the file as these are part of R. This is only needed in case of attribution requirements or other possible restrictions.",
    paste0(cran_policy_cookbook, "description_issues.html")
  )
)

# Helpers ---------------------------------------------------------------------

# The package root, fixed when the file is sourced: test_path() is relative to
# the working directory, which a test may move.
cran_policy_root <- normalizePath(testthat::test_path("..", ".."), mustWork = FALSE)

cran_policy_has_sources <- function(root = cran_policy_root) {
  file.exists(file.path(root, "DESCRIPTION")) && dir.exists(file.path(root, "R"))
}

cran_policy_hits <- function(rule = character(), file = character(), line = NA_integer_,
                             detail = character(), key = file) {
  n <- length(rule)
  data.frame(
    rule = rule, file = file, line = rep_len(as.integer(line), n),
    detail = rep_len(detail, n), key = rep_len(key, n),
    stringsAsFactors = FALSE
  )
}

cran_policy_bind <- function(parts) {
  parts <- Filter(function(x) !is.null(x) && nrow(x) > 0, parts)
  if (length(parts) == 0) {
    return(cran_policy_hits())
  }
  do.call(rbind, parts)
}

cran_policy_marker <- function(rule) {
  paste0("cran-policy:[[:space:]]*allow[[:space:]]+", rule, "([^[:alnum:]-]|$)")
}

# Files R CMD build keeps: .Rbuildignore patterns are Perl regular
# expressions, matched case-insensitively against every path and every parent
# directory relative to the root.
cran_policy_list <- function(root, dirs, pattern) {
  dirs <- dirs[dir.exists(file.path(root, dirs))]
  files <- unlist(lapply(dirs, function(d) {
    file.path(d, list.files(file.path(root, d), pattern = pattern, recursive = TRUE, all.files = TRUE))
  }))
  cran_policy_kept(root, files[!dir.exists(file.path(root, files))])
}

cran_policy_kept <- function(root, files) {
  ignore_file <- file.path(root, ".Rbuildignore")
  if (length(files) == 0 || !file.exists(ignore_file)) {
    return(sort(files))
  }
  patterns <- trimws(readLines(ignore_file, warn = FALSE))
  patterns <- patterns[nzchar(patterns) & !startsWith(patterns, "#")]
  ignored <- vapply(files, function(f) {
    parts <- strsplit(f, "/", fixed = TRUE)[[1]]
    paths <- vapply(seq_along(parts), function(i) paste(parts[seq_len(i)], collapse = "/"), character(1))
    any(vapply(patterns, function(p) any(grepl(p, paths, perl = TRUE, ignore.case = TRUE)), logical(1)))
  }, logical(1))
  sort(files[!ignored])
}

cran_policy_read <- function(root, file) {
  readLines(file.path(root, file), warn = FALSE, encoding = "UTF-8")
}

# Parse data of a unit of code, or the parse error.
cran_policy_parse <- function(lines) {
  parsed <- tryCatch(
    parse(text = lines, keep.source = TRUE, encoding = "UTF-8"),
    error = function(e) conditionMessage(e)
  )
  if (is.character(parsed)) {
    return(list(pd = NULL, error = parsed))
  }
  pd <- utils::getParseData(parsed, includeText = TRUE)
  if (is.null(pd) || nrow(pd) == 0) {
    return(list(pd = NULL, error = NULL))
  }
  pd <- pd[order(pd$line1, pd$col1, -pd$line2, -pd$col2), ]
  rownames(pd) <- NULL
  list(pd = pd, error = NULL)
}

# For every token: the top-level expression it belongs to, the name of the
# function that expression defines ("" when it defines none), and how many
# function definitions enclose the token.
cran_policy_scopes <- function(pd) {
  parent <- pd$parent
  names(parent) <- pd$id
  fun_ids <- pd$parent[pd$token == "FUNCTION"]
  top <- pd$id
  depth <- as.integer(pd$id %in% fun_ids)
  repeat {
    up <- parent[as.character(top)]
    move <- !is.na(up) & up > 0
    if (!any(move)) break
    top[move] <- up[move]
    depth[move] <- depth[move] + (top[move] %in% fun_ids)
  }
  tops <- unique(top)
  names <- vapply(tops, function(t) {
    kids <- pd[pd$parent == t, ]
    op <- which(kids$token %in% c("LEFT_ASSIGN", "EQ_ASSIGN") & kids$text %in% c("<-", "="))
    if (length(op) == 1 && op > 1 && op < nrow(kids) && kids$id[op + 1] %in% fun_ids) {
      return(gsub("^[`'\"]|[`'\"]$", "", kids$text[op - 1]))
    }
    call <- which(pd$parent %in% kids$id & pd$token == "SYMBOL_FUNCTION_CALL")
    if (length(call) && pd$text[call[1]] == "setMethod") {
      generic <- kids$text[kids$token == "expr" & grepl("^[\"']", kids$text)]
      if (length(generic)) {
        return(paste0(gsub("[\"']", "", generic[1]), ".S4"))
      }
    }
    ""
  }, character(1))
  list(top = top, depth = depth, fun = unname(names[match(top, tops)]))
}

# The whole call a SYMBOL_FUNCTION_CALL token belongs to.
cran_policy_call_text <- function(pd, rows) {
  vapply(rows, function(i) {
    fun_expr <- pd$parent[i]
    call <- pd$parent[match(fun_expr, pd$id)]
    pd$text[match(call, pd$id)]
  }, character(1))
}

# Units of code ---------------------------------------------------------------

# Vignette code chunks, with every other line blanked so that line numbers
# stay those of the file. Chunks that are not evaluated, or not R, are left
# out: an install.packages() shown with eval = FALSE is instruction, not code
# CRAN runs.
cran_policy_chunks <- function(lines) {
  out <- rep("", length(lines))
  i <- 1
  while (i <= length(lines)) {
    rmd <- grepl("^[[:space:]]*```+[[:space:]]*\\{[rR]([[:space:],}]|$)", lines[i])
    rnw <- grepl("^<<.*>>=[[:space:]]*$", lines[i])
    if (!rmd && !rnw) {
      i <- i + 1
      next
    }
    end_pattern <- if (rmd) "^[[:space:]]*```+[[:space:]]*$" else "^@[[:space:]]*$"
    end <- i + 1
    while (end <= length(lines) && !grepl(end_pattern, lines[end])) end <- end + 1
    body <- seq_len(max(0, min(end, length(lines) + 1) - i - 1)) + i
    no_eval <- grepl("eval[[:space:]]*=[[:space:]]*(FALSE|F)\\b", lines[i]) ||
      any(grepl("^[[:space:]]*#\\|[[:space:]]*eval:[[:space:]]*false", lines[body]))
    if (!no_eval) out[body] <- lines[body]
    i <- end + 1
  }
  out
}

# Every unit of R code the rules read: R/, tests/, vignette chunks and the
# code of each help page's examples.
cran_policy_units <- function(root, pages) {
  unit <- function(file, kind, lines) list(file = file, kind = kind, lines = lines)
  units <- list()
  for (f in cran_policy_list(root, "R", "[.][RrSsq]$")) {
    units[[length(units) + 1]] <- unit(f, "R", cran_policy_read(root, f))
  }
  for (f in cran_policy_list(root, "tests", "[.][Rr]$")) {
    units[[length(units) + 1]] <- unit(f, "tests", cran_policy_read(root, f))
  }
  for (f in cran_policy_list(root, "vignettes", "[.](Rmd|rmd|qmd|Rnw|rnw)$")) {
    units[[length(units) + 1]] <- unit(f, "vignettes", cran_policy_chunks(cran_policy_read(root, f)))
  }
  for (p in pages) {
    if (length(p$example_lines)) {
      units[[length(units) + 1]] <- unit(p$file, "examples", p$example_lines)
    }
  }
  units
}

# Help pages --------------------------------------------------------------------

cran_policy_pages <- function(root) {
  macros <- tryCatch(tools::loadPkgRdMacros(root), error = function(e) NULL)
  lapply(cran_policy_list(root, "man", "[.][Rr]d$"), function(f) {
    rd <- tryCatch(
      suppressWarnings(tools::parse_Rd(file.path(root, f), macros = macros)),
      error = function(e) conditionMessage(e)
    )
    if (is.character(rd)) {
      return(list(file = f, error = rd))
    }
    tags <- vapply(rd, function(x) attr(x, "Rd_tag"), character(1))
    field <- function(tag) unlist(lapply(rd[tags == tag], function(x) trimws(as.character(x))))
    out <- tempfile(fileext = ".R")
    on.exit(unlink(out))
    tools::Rd2ex(rd, out, commentDontrun = FALSE, commentDonttest = FALSE)
    example_lines <- if (file.exists(out)) readLines(out, warn = FALSE) else character()
    list(
      file = f, error = NULL,
      aliases = field("\\alias"), doctype = field("\\docType"),
      has_value = any(tags == "\\value"), has_examples = any(tags == "\\examples"),
      examples = rd[tags == "\\examples"], example_lines = example_lines
    )
  })
}

cran_policy_namespace <- function(root) {
  if (!file.exists(file.path(root, "NAMESPACE"))) {
    return(list(exports = character(), patterns = character(), s3 = character()))
  }
  ns <- parseNamespaceFile(basename(root), dirname(root))
  s3 <- if (length(ns$S3methods)) paste(ns$S3methods[, 1], ns$S3methods[, 2], sep = ".") else character()
  list(exports = ns$exports, patterns = ns$exportPatterns, s3 = s3)
}

# Rules on code ---------------------------------------------------------------

cran_policy_code_hits <- function(unit) {
  parsed <- cran_policy_parse(unit$lines)
  if (!is.null(parsed$error)) {
    return(cran_policy_hits("parse", unit$file, NA, parsed$error))
  }
  pd <- parsed$pd
  if (is.null(pd)) {
    return(cran_policy_hits())
  }
  where <- if (unit$kind == "examples") paste(unit$file, "(examples)") else unit$file
  hit <- function(rule, rows, detail) {
    if (length(rows) == 0) {
      return(NULL)
    }
    cran_policy_hits(rep(rule, length(rows)), where, pd$line1[rows], detail, key = unit$file)
  }
  is_r <- unit$kind == "R"
  calls <- which(pd$token == "SYMBOL_FUNCTION_CALL")
  call_text <- cran_policy_call_text(pd, calls)
  names(call_text) <- calls
  calls_to <- function(funs) calls[pd$text[calls] %in% funs]
  text_of <- function(rows) unname(call_text[as.character(rows)])
  scopes <- cran_policy_scopes(pd)
  out <- list()

  # T and F: a symbol, not `x$T`, not an argument name
  terminals <- which(pd$terminal)
  prev <- c(NA, pd$text[terminals][-length(terminals)])
  names(prev) <- terminals
  tf <- which(pd$token == "SYMBOL" & pd$text %in% c("T", "F"))
  tf <- tf[!(prev[as.character(tf)] %in% c("$", "@"))]
  out$tf <- hit("true-false", tf, paste0("`", pd$text[tf], "` for ", ifelse(pd$text[tf] == "T", "TRUE", "FALSE")))

  # installing packages; in R/ a function named install_* may do it
  installers <- c(
    "install.packages", "install_github", "install_gitlab", "install_bitbucket",
    "install_url", "install_version", "install_local", "pkg_install"
  )
  ins <- calls_to(installers)
  bioc <- calls_to("install")
  ins <- c(ins, bioc[grepl("^BiocManager::install", text_of(bioc))])
  if (is_r) ins <- ins[!grepl("^install", scopes$fun[ins], ignore.case = TRUE)]
  out$install <- hit("install-packages", ins, paste0(pd$text[ins], "()"))

  rm_ls <- calls_to("rm")
  rm_ls <- rm_ls[grepl("list[[:space:]]*=[[:space:]]*ls[[:space:]]*\\(", text_of(rm_ls))]
  out$rm <- hit("rm-ls", rm_ls, "rm(list = ls())")

  if (!is_r) {
    cores <- calls_to("detectCores")
    out$cores <- hit("cores", cores, "detectCores()")
  }

  if (is_r) {
    seed <- calls_to("set.seed")
    seed <- seed[grepl(
      "set[.]seed\\([[:space:]]*(seed[[:space:]]*=[[:space:]]*)?[-+]?[0-9][0-9.eE]*L?[[:space:]]*[,)]",
      text_of(seed)
    )]
    out$seed <- hit("set-seed", seed, "set.seed() with a fixed number")

    methods <- "^(print|format|summary|str|show|toString|plot|autoplot)[.]"
    console <- calls_to(c("cat", "print"))
    console <- console[!grepl(methods, scopes$fun[console])]
    out$console <- hit("print-cat", console, paste0(pd$text[console], "() outside a print method"))

    has_on_exit <- scopes$top[calls_to("on.exit")]
    state <- c(
      calls_to(c("setwd", "Sys.setenv", "Sys.setlocale")),
      {
        op <- calls_to(c("options", "par"))
        op[grepl("^[^(]*\\([[:space:]]*[A-Za-z._][A-Za-z0-9._]*[[:space:]]*=[^=]", text_of(op))]
      }
    )
    state <- state[!(scopes$top[state] %in% has_on_exit)]
    out$state <- hit("reset-state", state, paste0(pd$text[state], "() without on.exit()"))
    warn <- calls_to("options")
    warn <- warn[grepl("warn[[:space:]]*=[[:space:]]*-[[:space:]]*1\\b", text_of(warn))]
    out$warn <- hit("reset-state", warn, "options(warn = -1)")

    ge <- which((pd$token == "SYMBOL" & pd$text == ".GlobalEnv") |
      (pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == "globalenv"))
    out$ge <- hit("global-env", ge, paste0(pd$text[ge], " in package code"))

    # <<- is fine when it updates a variable of an enclosing function
    lhs_root <- function(op_rows, side) {
      vapply(op_rows, function(i) {
        kids <- pd[pd$parent == pd$parent[i], ]
        k <- match(pd$id[i], kids$id) + if (side == "left") -1L else 1L
        if (k < 1 || k > nrow(kids)) {
          return("")
        }
        target <- kids$text[k]
        sub("^[`]?([A-Za-z.][A-Za-z0-9._]*).*$", "\\1", target)
      }, character(1))
    }
    binds <- which((pd$token %in% c("LEFT_ASSIGN", "EQ_ASSIGN") & pd$text %in% c("<-", "=")) |
      pd$token == "SYMBOL_FORMALS")
    formal <- pd$token[binds] == "SYMBOL_FORMALS"
    bound_names <- pd$text[binds]
    bound_names[!formal] <- lhs_root(binds[!formal], "left")
    bound <- data.frame(top = scopes$top[binds], name = bound_names)
    super <- which(pd$token == "LEFT_ASSIGN" & pd$text == "<<-")
    super_r <- which(pd$token == "RIGHT_ASSIGN" & pd$text == "->>")
    targets <- c(lhs_root(super, "left"), lhs_root(super_r, "right"))
    super <- c(super, super_r)
    unbound <- vapply(seq_along(super), function(j) {
      i <- super[j]
      scopes$depth[i] < 2 ||
        !any(bound$top == scopes$top[i] & bound$name == targets[j])
    }, logical(1))
    out$super <- hit("global-env", super[unbound], paste0("<<- to `", targets[unbound], "`, which no enclosing function binds"))

    ip <- calls_to("installed.packages")
    out$ip <- hit("installed-packages", ip, "installed.packages()")

    # argument defaults
    eq <- which(pd$token == "EQ_FORMALS")
    default_text <- vapply(eq, function(i) {
      sib <- pd[pd$parent == pd$parent[i], ]
      k <- match(pd$id[i], sib$id)
      if (k < nrow(sib)) sib$text[k + 1] else ""
    }, character(1))
    home <- eq[grepl("^([\"'](\\.|~|~/.*)[\"']|getwd\\(\\))$", default_text)]
    out$home <- hit("home-default", home, paste0("default ", default_text[match(home, eq)]))
    cores <- eq[grepl("detectCores\\(", default_text)]
    out$cores_default <- hit("cores", cores, "detectCores() as a default")
  }

  hits <- cran_policy_bind(out)
  if (nrow(hits) == 0) {
    return(hits)
  }
  allowed <- vapply(seq_len(nrow(hits)), function(i) {
    !is.na(hits$line[i]) && grepl(cran_policy_marker(hits$rule[i]), unit$lines[hits$line[i]])
  }, logical(1))
  hits[!allowed, ]
}

# Rules on text and help pages --------------------------------------------------

# name, three colons, name: not a Pandoc fenced div
cran_policy_triple_colon_lines <- function(lines) {
  hit <- grepl("[[:alnum:]._]:{3}[[:alpha:]._`]", lines)
  which(hit & !grepl(cran_policy_marker("triple-colon"), lines))
}

cran_policy_text_hits <- function(root, settings) {
  dirs <- c("R", "man", "vignettes", "inst", if (isTRUE(settings$scan_tests)) "tests")
  top <- c("DESCRIPTION", "README.md", "NEWS.md")
  files <- c(
    cran_policy_list(root, dirs, "[.](R|r|S|s|q|Rmd|rmd|qmd|Rnw|rnw|Rd|rd|md)$"),
    cran_policy_kept(root, top[file.exists(file.path(root, top))])
  )
  cran_policy_bind(lapply(files, function(f) {
    lines <- cran_policy_triple_colon_lines(cran_policy_read(root, f))
    if (length(lines)) cran_policy_hits(rep("triple-colon", length(lines)), f, lines, "triple colon")
  }))
}

# A comment line whose text, without the hash, parses as a call.
cran_policy_commented_code <- function(lines) {
  markers <- "^[[:space:]]*(### |## (No test:|End\\(No test\\)|Don't show:|End\\(Don't show\\)))"
  candidates <- which(grepl("^[[:space:]]*#", lines) & !grepl(markers, lines))
  candidates[vapply(candidates, function(i) {
    body <- sub("^[[:space:]]*#+'?[[:space:]]?", "", lines[i])
    if (!nzchar(trimws(body)) || grepl(cran_policy_marker("rd-commented-code"), lines[i])) {
      return(FALSE)
    }
    exprs <- tryCatch(parse(text = body, keep.source = FALSE), error = function(e) NULL)
    length(exprs) > 0 && any(vapply(as.list(exprs), is.call, logical(1)))
  }, logical(1))]
}

# The \dontrun{} blocks of an \examples section whose first line is not a comment.
cran_policy_dontrun_unexplained <- function(examples) {
  n <- 0L
  walk <- function(x) {
    for (el in x) {
      if (identical(attr(el, "Rd_tag"), "\\dontrun")) {
        text <- paste(unlist(lapply(el, as.character)), collapse = "")
        first <- trimws(strsplit(text, "\n", fixed = TRUE)[[1]])
        first <- first[nzchar(first)][1]
        if (is.na(first) || !startsWith(first, "#")) n <<- n + 1L
      } else if (is.list(el)) {
        walk(el)
      }
    }
  }
  walk(examples)
  n
}

cran_policy_page_hits <- function(pages, functions, ns) {
  exported <- function(x) {
    x %in% ns$exports || x %in% ns$s3 ||
      any(vapply(ns$patterns, function(p) grepl(p, x), logical(1)))
  }
  cran_policy_bind(lapply(pages, function(p) {
    if (!is.null(p$error)) {
      return(cran_policy_hits("parse", p$file, NA, p$error))
    }
    if (any(p$doctype %in% c("package", "data", "class", "methods"))) {
      return(NULL)
    }
    fns <- intersect(p$aliases, functions)
    public <- fns[vapply(fns, exported, logical(1))]
    private <- setdiff(fns, public)
    out <- list()
    if (length(public) && !p$has_value) {
      out$value <- cran_policy_hits("rd-value", p$file, NA, paste0("no \\value for ", paste0(public, "()", collapse = ", ")))
    }
    if (length(public) && !p$has_examples) {
      out$examples <- cran_policy_hits("rd-exported-no-examples", p$file, NA, paste0("no \\examples for ", paste0(public, "()", collapse = ", ")))
    }
    if (length(private) && p$has_examples) {
      out$private <- cran_policy_hits("rd-examples-unexported", p$file, NA, paste0("examples for unexported ", paste0(private, "()", collapse = ", ")))
    }
    n <- cran_policy_dontrun_unexplained(p$examples)
    if (n > 0) {
      out$dontrun <- cran_policy_hits("rd-dontrun-reason", p$file, NA, sprintf("%d \\dontrun{} block(s) without a comment giving the reason", n))
    }
    commented <- cran_policy_commented_code(p$example_lines)
    if (length(commented)) {
      out$commented <- cran_policy_hits(
        rep("rd-commented-code", length(commented)), paste(p$file, "(examples)"), commented,
        trimws(p$example_lines[commented]),
        key = p$file
      )
    }
    cran_policy_bind(out)
  }))
}

# Rules on DESCRIPTION --------------------------------------------------------

cran_policy_description_hits <- function(root) {
  desc <- read.dcf(file.path(root, "DESCRIPTION"))[1, ]
  field <- function(x) if (x %in% names(desc)) gsub("[[:space:]]+", " ", trimws(desc[[x]])) else ""
  title <- field("Title")
  description <- field("Description")
  out <- list()
  if (grepl("\\b(in|for|with|using) '?R'?([^[:alnum:]]|$)", title)) {
    out$r <- cran_policy_hits("desc-title", "DESCRIPTION", NA, paste0("'R' in the Title: ", title), key = "R")
  }
  if (nchar(title) > 65) {
    out$long <- cran_policy_hits("desc-title", "DESCRIPTION", NA, sprintf("Title has %d characters", nchar(title)), key = "length")
  }
  if (grepl("^Functions for", description) ||
    (nzchar(title) && startsWith(tolower(description), tolower(title)))) {
    out$start <- cran_policy_hits("desc-description-start", "DESCRIPTION", NA, substr(description, 1, 40), key = "start")
  }
  base_packages <- c(
    "R", "base", "compiler", "datasets", "graphics", "grDevices", "grid", "methods",
    "parallel", "splines", "stats", "stats4", "tcltk", "tools", "utils"
  )
  deps <- unlist(lapply(c("Depends", "Imports", "Suggests", "LinkingTo", "Enhances"), function(x) {
    trimws(sub("[[:space:](].*$", "", strsplit(field(x), ",", fixed = TRUE)[[1]]))
  }))
  deps <- setdiff(unique(deps[nzchar(deps)]), base_packages)
  text <- paste(title, description)
  bare <- deps[vapply(deps, function(d) {
    grepl(paste0("(?<![A-Za-z0-9.'/_-])", gsub(".", "\\.", d, fixed = TRUE), "(?![A-Za-z0-9'_/-]|[.][A-Za-z0-9])"), text, perl = TRUE)
  }, logical(1))]
  if (length(bare)) {
    out$quote <- cran_policy_hits(rep("desc-quote-packages", length(bare)), "DESCRIPTION", NA, paste0("'", bare, "' is not quoted"), key = bare)
  }
  authors <- field("Authors@R")
  if (nzchar(authors)) {
    people <- tryCatch(
      eval(str2lang(authors), list(person = utils::person, c = c), baseenv()),
      error = function(e) NULL
    )
    roles <- unlist(lapply(unclass(people), function(p) p$role))
    if (!is.null(people) && !("cph" %in% roles)) {
      out$cph <- cran_policy_hits("desc-cph", "DESCRIPTION", NA, "no person with role 'cph' in Authors@R", key = "cph")
    }
  }
  license <- field("License")
  if (grepl("file[[:space:]]+LICEN[CS]E", license) &&
    !grepl("^[[:space:]]*(MIT|BSD_2_clause|BSD_3_clause)\\b", license)) {
    out$license <- cran_policy_hits("desc-license-file", "DESCRIPTION", NA, license, key = "license")
  }
  cran_policy_bind(out)
}

# All rules -------------------------------------------------------------------

cran_policy_check <- function(root, settings = cran_policy_settings) {
  pages <- cran_policy_pages(root)
  units <- cran_policy_units(root, pages)
  functions <- unlist(lapply(Filter(function(u) u$kind == "R", units), function(u) {
    parsed <- cran_policy_parse(u$lines)
    if (is.null(parsed$pd)) {
      return(character())
    }
    unique(cran_policy_scopes(parsed$pd)$fun)
  }))
  hits <- cran_policy_bind(c(
    list(cran_policy_text_hits(root, settings)),
    list(cran_policy_page_hits(pages, setdiff(functions, ""), cran_policy_namespace(root))),
    lapply(units, cran_policy_code_hits),
    list(cran_policy_description_hits(root))
  ))
  allowed <- vapply(seq_len(nrow(hits)), function(i) {
    hits$key[i] %in% settings$allow[[hits$rule[i]]]
  }, logical(1))
  hits[!allowed, ]
}

cran_policy_report <- function(rule, hits) {
  where <- ifelse(is.na(hits$line), hits$file, paste0(hits$file, ":", hits$line))
  paste(c(
    sprintf("CRAN policy rule `%s`: %s", rule, cran_policy_rules[[rule]][1]),
    sprintf("Source: %s", cran_policy_rules[[rule]][2]),
    paste0("  ", where, ": ", hits$detail)
  ), collapse = "\n")
}

# The package -----------------------------------------------------------------

test_that("the package sources follow the CRAN reviewer rules", {
  skip_if_not(
    cran_policy_has_sources(),
    "package sources not available (R CMD check runs the installed tests)"
  )
  hits <- cran_policy_check(cran_policy_root)
  for (rule in names(cran_policy_rules)) {
    found <- hits[hits$rule == rule, ]
    testthat::expect(nrow(found) == 0, cran_policy_report(rule, found))
  }
})

# Self-tests: every rule fires on a planted case --------------------------------

# A minimal package with one violation per rule (bad = TRUE) or none. The
# triple colon is assembled, so that this file does not flag itself.
cran_policy_fixture <- function(bad) {
  root <- tempfile("cranpolicy")
  for (d in c("R", "man", "tests/testthat", "vignettes/articles")) {
    dir.create(file.path(root, d), recursive = TRUE)
  }
  put <- function(path, ...) writeLines(c(...), file.path(root, path))
  tc <- strrep(":", 3)

  put(
    "DESCRIPTION",
    "Package: fixturepkg",
    if (bad) "Title: Tidy Example Data in R" else "Title: Tidy Example Data",
    "Version: 0.0.1",
    sprintf(
      "Authors@R: person(\"Ada\", \"Lovelace\", email = \"ada@example.org\", role = c(%s))",
      if (bad) "\"aut\", \"cre\"" else "\"aut\", \"cre\", \"cph\""
    ),
    if (bad) "Description: Functions for example data in 'JSON' via 'jsonlite' and jsonlite." else
      "Description: Generates example data in 'JSON' through the 'jsonlite' package.",
    if (bad) "License: GPL-3 + file LICENSE" else "License: GPL-3",
    "Imports: jsonlite"
  )
  put(".Rbuildignore", "^vignettes/articles$")
  put(
    "NAMESPACE",
    "export(good_fun)", "export(install_helper)", "export(talk)", "S3method(print, thing)"
  )
  put(
    "R/good.R",
    "good_fun <- function(x, seed = NULL, path = tempdir()) {",
    "  if (!is.null(seed)) set.seed(seed)",
    "  old <- options(digits = 3)",
    "  on.exit(options(old))",
    "  total <- 0",
    "  add <- function(y) total <<- total + y",
    "  lapply(x, add)",
    "  list(total = total, flag = TRUE, t = x$T, path = path)",
    "}",
    "print.thing <- function(x, ...) {",
    "  cat(\"thing\\n\")",
    "  invisible(x)",
    "}",
    "talk <- function() cat(\"hi\") # cran-policy: allow print-cat verbose by design",
    "internal_fun <- function() NULL",
    "install_helper <- function(pkg) utils::install.packages(pkg)"
  )
  if (bad) {
    put(
      "R/bad.R",
      "tf_fun <- function() F",
      "seed_fun <- function() set.seed(42)",
      "loud_fun <- function() cat(\"hello\")",
      "wd_fun <- function(d) setwd(d)",
      "ge_fun <- function() counter <<- 1",
      "ip_fun <- function() installed.packages()",
      "ins_fun <- function() install.packages(\"x\")",
      "out_fun <- function(path = \".\") path",
      paste0("peek <- function() fixturepkg", tc, "internal_fun()")
    )
  }
  rd <- function(name, title, value = TRUE, examples = NULL) {
    c(
      sprintf("\\name{%s}", name), sprintf("\\alias{%s}", name),
      sprintf("\\title{%s}", title), "\\description{A function.}",
      sprintf("\\usage{%s()}", name),
      if (value) "\\value{Nothing.}",
      if (!is.null(examples)) c("\\examples{", examples, "}")
    )
  }
  put(
    "man/good_fun.Rd",
    rd(
      "good_fun", "Good", value = !bad,
      examples = c(
        "good_fun(1:3)",
        "\\dontrun{",
        if (!bad) "# needs a server",
        "good_fun(4)",
        "}",
        if (bad) "# good_fun(2)"
      )
    )
  )
  put("man/talk.Rd", rd("talk", "Talk", examples = "talk()"))
  put(
    "man/install_helper.Rd",
    rd("install_helper", "Install", examples = if (!bad) c("\\dontrun{", "# installs from CRAN", "install_helper(\"x\")", "}"))
  )
  if (bad) {
    put("man/internal_fun.Rd", rd("internal_fun", "Internal", examples = "internal_fun()"))
  }
  put(
    "vignettes/intro.Rmd",
    "---", "title: Intro", "---", "",
    "```{r}", "library(fixturepkg)", if (bad) "n <- parallel::detectCores()", "```", "",
    "```{r, eval = FALSE}", "install.packages(\"fixturepkg\")", "```", "",
    "```{r}", "#| eval: false", "rm(list = ls())", "```", "",
    "```{bash}", "echo T", "```"
  )
  put("vignettes/articles/extra.Rmd", "```{r}", "x <- T", "rm(list = ls())", "```")
  put(
    "tests/testthat/test-good.R",
    "test_that(\"works\", expect_true(TRUE))",
    if (bad) "rm(list = ls())"
  )
  root
}

test_that("every rule fires once on a package that breaks it, never on a clean one", {
  skip_on_cran()
  good <- cran_policy_fixture(bad = FALSE)
  bad <- cran_policy_fixture(bad = TRUE)

  good_hits <- cran_policy_check(good, list(scan_tests = TRUE, allow = list()))
  expect_equal(paste(good_hits$rule, good_hits$file, good_hits$detail), character())

  bad_hits <- cran_policy_check(bad, list(scan_tests = TRUE, allow = list()))
  rules <- setdiff(names(cran_policy_rules), "parse")
  counts <- table(factor(bad_hits$rule, levels = names(cran_policy_rules)))
  expect_equal(as.vector(counts[rules]), rep(1L, length(rules)), label = paste(rules, collapse = ", "))
  expect_equal(unname(counts["parse"]), 0L)

  # a page-level exception in the settings
  allowed <- cran_policy_check(bad, list(scan_tests = TRUE, allow = list("rd-value" = "man/good_fun.Rd")))
  expect_false("rd-value" %in% allowed$rule)

  unlink(c(good, bad), recursive = TRUE)
})

# One unit of code in, the hits of one rule out.
cran_policy_try <- function(rule, code, kind = "R") {
  hits <- cran_policy_code_hits(list(file = "x.R", kind = kind, lines = code))
  sum(hits$rule == rule)
}

test_that("the code rules tell the offending form from the accepted one", {
  skip_on_cran()
  expect_equal(cran_policy_try("true-false", "x <- T"), 1)
  expect_equal(cran_policy_try("true-false", "f(y = F)", kind = "tests"), 1)
  expect_equal(cran_policy_try("true-false", c("x$T", "f(T = 1)", "'T'", "TRUE", "# T")), 0)

  expect_equal(cran_policy_try("set-seed", "f <- function() set.seed(seed = 1L)"), 1)
  expect_equal(cran_policy_try("set-seed", "f <- function(seed = NULL) if (!is.null(seed)) set.seed(seed)"), 0)
  expect_equal(cran_policy_try("set-seed", "set.seed(1)", kind = "tests"), 0)

  expect_equal(cran_policy_try("print-cat", "f <- function(x) print(x)"), 1)
  expect_equal(cran_policy_try("print-cat", c(
    "print.foo <- function(x, ...) cat('foo')",
    "format.foo <- function(x, ...) print(x)",
    "f <- function() cli::cat_line('x')",
    "g <- function() cat('x') # cran-policy: allow print-cat verbose only"
  )), 0)

  expect_equal(cran_policy_try("reset-state", "f <- function() options(digits = 3)"), 1)
  expect_equal(cran_policy_try("reset-state", "f <- function() { op <- options(warn = -1); on.exit(options(op)) }"), 1)
  expect_equal(cran_policy_try("reset-state", c(
    "f <- function(d) { old <- setwd(d); on.exit(setwd(old)) }",
    "g <- function() getOption('digits')",
    "h <- function() options('digits')",
    "k <- function() { op <- par(mfrow = c(1, 2)); on.exit(par(op)) }"
  )), 0)

  expect_equal(cran_policy_try("global-env", "f <- function() assign('x', 1, envir = .GlobalEnv)"), 1)
  expect_equal(cran_policy_try("global-env", "f <- function() { g <- function() y <<- 2; g() }"), 1)
  expect_equal(cran_policy_try("global-env", "f <- function() 2 ->> z"), 1)
  expect_equal(cran_policy_try("global-env", c(
    "f <- function() { n <- 0; g <- function() n <<- n + 1; g(); n }",
    "h <- function(n) { g <- function() n <<- 2; g() }",
    "k <- function() { acc <- list(); g <- function(x) acc$y <<- x; g(1) }"
  )), 0)

  expect_equal(cran_policy_try("install-packages", "f <- function() BiocManager::install('x')"), 1)
  expect_equal(cran_policy_try("install-packages", "f <- function() remotes::install_github('a/b')"), 1)
  expect_equal(cran_policy_try("install-packages", "install.packages('x')", kind = "examples"), 1)
  expect_equal(cran_policy_try("install-packages", "install_deps <- function() utils::install.packages('x')"), 0)

  expect_equal(cran_policy_try("cores", "f <- function(cores = parallel::detectCores()) cores"), 1)
  expect_equal(cran_policy_try("cores", "n <- parallel::detectCores()", kind = "tests"), 1)
  expect_equal(cran_policy_try("cores", "f <- function(cores = 2L) cores"), 0)

  expect_equal(cran_policy_try("home-default", "f <- function(dir = getwd()) dir"), 1)
  expect_equal(cran_policy_try("home-default", "f <- function(file = '~/out.csv') file"), 1)
  expect_equal(cran_policy_try("home-default", c("f <- function(path = tempdir()) path", "g <- function(path) path")), 0)

  expect_equal(cran_policy_try("rm-ls", "rm(list = ls())", kind = "examples"), 1)
  expect_equal(cran_policy_try("rm-ls", "rm(x)", kind = "examples"), 0)

  expect_equal(cran_policy_try("parse", "f <- function( {"), 1)
})

test_that("the text and example rules tell the offending form from the accepted one", {
  skip_on_cran()
  tc <- strrep(":", 3)
  expect_equal(
    cran_policy_triple_colon_lines(c(
      paste0("x <- pkg", tc, "f()"),
      paste0("pkg", tc, "`f<-`"),
      "pkg::f()",
      paste(tc, "{.callout-note}"),
      strrep(":", 4),
      paste0("y <- pkg", tc, "g() # cran-policy: allow triple-colon comparison with an internal")
    )),
    1:2
  )

  expect_equal(
    cran_policy_commented_code(c(
      "# plot(x)",
      "# needs a JATOS server and a stored API token",
      "#> [1] 1 2 3",
      "## No test: ",
      "## End(No test)",
      "### ** Examples",
      "# TRUE",
      "# f(x) # cran-policy: allow rd-commented-code shown, not run"
    )),
    1L
  )

  vignette <- c(
    "```{r}", "x <- T", "```",
    "```{r, eval = FALSE}", "y <- F", "```",
    "```{python}", "z = T", "```"
  )
  chunks <- cran_policy_chunks(vignette)
  expect_equal(which(nzchar(chunks)), 2L)
  hits <- cran_policy_code_hits(list(file = "v.Rmd", kind = "vignettes", lines = chunks))
  expect_equal(hits$line, 2L)
})
