make_po_dir <- function(pkg = ".") {
    pkg <- as.package(pkg)
    po_dir <- file.path(pkg$path, "po")
    dir.create(po_dir, FALSE)
    return(po_dir)
}

make_template <- 
function(pkg = ".", 
         created = format(Sys.time(), "%Y-%m-%d %H:%M"),
         maintainer,
         translator,
         team,
         charset = "UTF-8",
         domain = "R") {
    # generate internal msgtemplate representation (calling `xgettext` and `xngettext`)
    pkg <- as.package(pkg)
    
    template <- 
    c("msgid \"\"", 
      "msgstr \"\"", 
      sprintf("\"Project-Id-Version: %s %s\\n\"", pkg$package, pkg$version), 
      sprintf("\"Report-Msgid-Bugs-To: %s\\n\"", if(!missing(maintainer)) format(maintainer) else pkg$maintainer), 
      paste0("\"POT-Creation-Date: ", created, "\\n\""), 
      paste0("\"PO-Revision-Date: ", format(Sys.time(), "%Y-%m-%d %H:%M"), "\\n\""), 
      paste0("\"Last-Translator: ", if(!missing(translator)) format(translator) else NULL, "\\n\""), 
      paste0("\"Language-Team: ", if(!missing(team)) format(team) else NULL, "\\n\""), 
      "\"Language: LL\\n\"",
      "\"MIME-Version: 1.0\\n\"", 
      paste0("\"Content-Type: text/plain; charset=", charset, "\\n\""), 
      "\"Content-Transfer-Encoding: 8bit\\n\"")
    
    # run xgettext
    tmp <- unique(unlist(get_messages(pkg = pkg, type = "gettext")))
    tmp <- tmp[nzchar(tmp)]
    if (length(tmp) > 0L) {
        tmp <- shQuote(encodeString(tmp), type = "cmd")
        template <- c(template, paste0("\nmsgid ",tmp,"\nmsgstr \"\""))
    }
    
    # run xngettext
    tmp <- get_messages(pkg = pkg, type = "ngettext")
    un <- unique(unlist(tmp, recursive = TRUE))
    for (ee in tmp) {
        for (e in ee) {
            if (e[1L] %in% un) {
               template <- c(template, paste0(paste0("\nmsgid  ", shQuote(encodeString(e[1L])), "\""),
                                              paste0("\nmsgid_plural \"", shQuote(encodeString(e[1L])), "\""), 
                                              "\nmsgstr[0]    \"", "\nmsgstr[1]    \""))
                un <- un[-match(e, un)]
            }
        }
    }
    
    # parse template to internal representation
    structure(parse_template(template), domain = domain)
}

use_translations <- 
function(pkg = ".", 
         domain = "R",
         ...) {
    pkg <- as.package(pkg)

    po_dir <- file.path(pkg$path, "po")
    if(!file.exists(po_dir))
        po_dir <- make_po_dir(pkg = pkg)
    template_file <- file.path(pkg$path, "po", paste0(if(domain == "R") "R-" else NULL, pkg$package, ".pot"))
    
    template <- make_template(pkg = pkg, domain = domain, ...)
    if(template_exists(pkg = pkg)) {
        current <- template_current(pkg = pkg, template = template)
        if(current) {
            message("The .pot template file has not changed")
        } else {
            template$"POT-Creation-Date" <- attributes(current)$"template_file"$"POT-Creation-Date"
            write_template(template, domain = attributes(template)$domain)
        }
    } else {
        write_template(template, domain = attributes(template)$domain)
    }
    return(invisible(template))
}

template_exists <- function(pkg = ".", domain = "R") {
    pkg <- as.package(pkg)
    template_file <- file.path(pkg$path, "po", paste0(if(domain == "R") "R-" else NULL, pkg$package, ".pot"))
    file.exists(template_file)
}

gettext_msg <- function(msg) {
    structure(list(msgid = msg, msgstr = ""), class = "gettext_msg")
}

print.gettext_msg <- function(x, ...) {
    cat("msgid: ", x$msgid, "\n")
    cat("msgstr: ", x$msgstr, "\n\n")
    invisible(x)
}

ngettext_msg <- function(msg, plural) {
    structure(list(msgid = msg, msgid_plural = plural, msgstr0 = "", msgstr1 = ""), class = "ngettext_msg")
}

print.ngettext_msg <- function(x, ...) {
    cat("msgid: ", x$msgid, "\n")
    cat("msgid_plural: ", x$msgid_plural, "\n")
    cat("msgstr[0]: ", x$msgstr0, "\n")
    cat("msgstr[1]: ", x$msgstr1, "\n\n")
    invisible(x)
}

parse_template <- function(template) {
    h <- gsub("[\"]$", "", gsub("^[\"]", "", template[!grepl("msgid", template)]))
    h <- read.dcf(textConnection(h[!grepl("msgstr", h)]))
    out <- setNames(as.list(h), colnames(h))
    
    gx <- grep("msgid", template)
    gn <- grep("msgid_plural", template)
    
    # parse `xgettext` messages
    gx <- gx[!gx %in% gn]
    msgids1 <- template[gx]
    msgids1 <- gsub("^\n", "", msgids1)
    msgids1 <- sapply(strsplit(msgids1, "\nmsgstr"), `[`, 1)
    msgids1 <- gsub("^msgid ", "", msgids1)
    msgids1 <- gsub("^[\"]", "", msgids1)
    msgids1 <- gsub("[\"]$", "", msgids1)
    msgids1 <- msgids1[msgids1 != ""]
    msgids1out <- lapply(msgids1, gettext_msg)[sort.list(msgids1)]
    out$msgids <- msgids1out
    
    # parse `nxgettext` messages
    msgids2 <- template[gn]
    msgids2 <- gsub("^\n", "", msgids2)
    msgids2 <- sapply(strsplit(msgids2, "\nmsgstr"), `[`, 1)
    s <- strsplit(msgids2, "\nmsgid_plural ")
    msgids2single <- sapply(s, `[`, 1)
    msgids2single <- gsub("^msgid  ", "", msgids2single)
    msgids2single <- gsub("^[\"]{1,2}", "", msgids2single)
    msgids2single <- gsub("[\"]+$", "", msgids2single)
    
    msgids2plural <- sapply(s, `[`, 2)
    msgids2plural <- gsub("^[\"]+", "", msgids2plural)
    msgids2plural <- gsub("[\"]+$", "", msgids2plural)
    
    msgids2out <- unname(mapply(ngettext_msg, msgids2single, msgids2plural, SIMPLIFY = FALSE)[sort.list(msgids2single)])
    out$msgids <- c(out$msgids, msgids2out)
    
    structure(out, class = "msgtemplate")
}

write_template <- function(template, pkg = ".", domain = "R") {
    pkg <- as.package(pkg)
    po_dir <- file.path(pkg$path, "po")
    if(!file.exists(po_dir))
        make_po_dir(pkg = pkg)
    template_file <- file.path(po_dir, paste0(if(domain == "R") "R-" else NULL, pkg$package, ".pot"))
    out <- c("msgid \"\"\nmsgstr \"\"")
    msgids <- template$msgids
    template$msgids <- NULL
    out <- c(out, paste0("\n\"", names(template),": ", unname(unlist(template)), "\""))
    
    for(i in seq_along(msgids)) {
        if(inherits(msgids[[i]], "gettext_msg")) {
            out <- c(out, paste0("\n\nmsgid \"", unlist(msgids[[i]]$msgid), "\"\nmsgstr \"\""))
        } else {
            out <- c(out, paste0("\n\nmsgid \"", unlist(msgids[[i]]$msgid), 
                                 "\"\nmsgid_plural \"", unlist(msgids[[i]]$msgid_plural), 
                                 "\"\nmsgstr[0] \"\"\nmsgstr[1] \"\""))
        }
    }
    writeLines(c(out,"\n"), con = template_file, sep = "")
}

read_template <- function(file, pkg = ".", domain = "R"){
    if(missing(file)) {
        pkg <- as.package(pkg)
        file <- file.path(pkg$path, "po", paste0(if(domain == "R") "R-" else NULL, pkg$package, ".pot"))
    }
    if(!file.exists(file))
        stop("The .pot template file not found")
    con <- file(file, "r")
    on.exit(close(con))
    template <- readLines(con)
    structure(parse_template(template), domain = domain)
}

template_current <- function(template, pkg = ".", domain = "R") {
    template_file <- read_template(pkg = pkg, domain = domain)
    
    # do not compare creation or revision dates
    template2 <- template
    template2$"PO-Revision-Date" <- template_file$"PO-Revision-Date"
    template2$"POT-Creation-Date" <- template_file$"POT-Creation-Date"
    structure(identical(template2, template_file), 
              comparison = all.equal(template2, template_file), 
              template = template, 
              template_file = template_file)
}

print.msgtemplate <- function(x, ...){
    invisible(x)
}