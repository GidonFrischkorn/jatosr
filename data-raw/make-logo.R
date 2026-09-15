# Generate the jatosr hex sticker entirely from R.
#
# The motif (a download arrow feeding a table) is original; only the JATOS
# colour palette is borrowed. The JATOS logo itself is not reproduced: JATOS
# is Apache-2.0 licensed and section 6 of that license withholds trademark
# permission, and the R logo (CC-BY-SA 4.0 / GPL-2) would force a share-alike
# license on the sticker. Colours are not copyrightable.
#
# Geometry follows the hexb.in standard: pointy-top hexagon, 2 in tall by
# 1.73 in wide (height:width = 2:sqrt(3)). Output sizes follow
# usethis::use_logo(): 240 x 278 px for man/figures/logo.png.
#
# Run from the package root:
#   source("data-raw/make-logo.R")
#   make_logo("man/figures/logo.png")                  (pkgdown / README size)
#   make_logo(file.path(tempdir(), "logo-print.png"), width_px = 2400)
#                                                      (print resolution)
#
# Needs ggplot2, ggforce, ragg, systemfonts (all in the development library,
# none in Imports).

.data <- rlang::.data

hex_palette <- list(
  dark = list(
    background = "#22354A", # deep blue-grey
    border     = "#FDCD08", # JATOS yellow
    arrow      = "#FDCD08",
    cell_new   = "#F4921F", # JATOS orange, freshly downloaded row
    cell_old   = "#E6ECF2", # settled rows
    text       = "#FFFFFF"
  ),
  light = list(
    background = "#FDCD08",
    border     = "#22354A",
    arrow      = "#22354A",
    cell_new   = "#F4921F",
    cell_old   = "#22354A",
    text       = "#22354A"
  )
)

# Pointy-top regular hexagon with circumradius `r`, centred at the origin.
hexagon <- function(r = 1) {
  angle <- seq(90, 450, by = 60) * pi / 180
  data.frame(x = r * cos(angle), y = r * sin(angle))
}

# Downward arrow: shaft from `top` to `tip + head_h`, head ending at `tip`.
arrow_polygon <- function(top = 0.73, tip = 0.35, shaft_w = 0.15,
                          head_w = 0.42, head_h = 0.17) {
  s <- shaft_w / 2
  h <- head_w / 2
  neck <- tip + head_h
  data.frame(
    x = c(-s, s, s, h, 0, -h, -s),
    y = c(top, top, neck, neck, tip, neck, neck)
  )
}

# 3 x 3 grid of table cells; the top row is the row that just arrived.
table_cells <- function(cols = c(-0.30, 0, 0.30),
                        rows = c(0.17, -0.01, -0.19),
                        w = 0.26, h = 0.15) {
  grid <- expand.grid(cx = cols, cy = rows)
  grid$cell <- seq_len(nrow(grid))
  grid$new <- grid$cy == max(rows)
  corners <- data.frame(
    dx = c(-1, 1, 1, -1) * w / 2,
    dy = c(-1, -1, 1, 1) * h / 2
  )
  out <- merge(grid, corners, by = NULL)
  out$x <- out$cx + out$dx
  out$y <- out$cy + out$dy
  out[order(out$cell), c("cell", "new", "x", "y")]
}

pick_font <- function(preferred = c("Avenir Next", "Source Sans 3",
                                    "Helvetica Neue")) {
  available <- systemfonts::system_fonts()$family
  hit <- preferred[preferred %in% available]
  if (length(hit) == 0) "sans" else hit[[1]]
}

hex_plot <- function(palette = hex_palette$dark, label = "jatosr",
                     font = pick_font(), border_width = 0.045,
                     text_size = 6, text_y = -0.50) {
  outer <- hexagon(1)
  inner <- hexagon(1 - border_width)
  cells <- table_cells()
  cells$fill <- ifelse(cells$new, palette$cell_new, palette$cell_old)

  xy <- ggplot2::aes(.data$x, .data$y)

  ggplot2::ggplot() +
    ggplot2::geom_polygon(data = outer, xy, fill = palette$border) +
    ggplot2::geom_polygon(data = inner, xy, fill = palette$background) +
    ggforce::geom_shape(
      data = cells,
      ggplot2::aes(.data$x, .data$y, group = .data$cell, fill = .data$fill),
      radius = grid::unit(1.2, "pt")
    ) +
    ggforce::geom_shape(
      data = arrow_polygon(), xy,
      fill = palette$arrow, radius = grid::unit(1.5, "pt")
    ) +
    ggplot2::annotate(
      "text", x = 0, y = text_y, label = label, family = font,
      fontface = "bold", colour = palette$text, size = text_size
    ) +
    ggplot2::scale_fill_identity() +
    ggplot2::coord_fixed(
      xlim = c(-1, 1) * sqrt(3) / 2, ylim = c(-1, 1), expand = FALSE
    ) +
    ggplot2::theme_void() +
    ggplot2::theme(plot.margin = grid::unit(c(0, 0, 0, 0), "pt"))
}

# Write the sticker as PNG with a transparent surround. `width_px` sets the
# pixel width; height follows the 2:sqrt(3) hex ratio (240 -> 278 as usethis).
make_logo <- function(path = "man/figures/logo.png", width_px = 240,
                      variant = c("dark", "light"), ...) {
  variant <- match.arg(variant)
  height_px <- round(width_px * 2 / sqrt(3))
  width_in <- 1.73
  dpi <- width_px / width_in
  p <- hex_plot(palette = hex_palette[[variant]], ...)
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  ragg::agg_png(path, width = width_px, height = height_px, units = "px",
                res = dpi, background = "transparent")
  print(p)
  grDevices::dev.off()
  invisible(path)
}
