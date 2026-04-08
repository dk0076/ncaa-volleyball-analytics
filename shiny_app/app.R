library(shiny)
library(dplyr)
library(ggplot2)
library(ggrepel)
library(here)

serves      <- readRDS(here("data", "serve_quality.rds"))
val_metrics <- if (file.exists(here("data", "validation_metrics.rds"))) {
  readRDS(here("data", "validation_metrics.rds"))
} else NULL

# Summarize for leaderboard — OOF columns throughout for consistency with stated methodology.
# quality_index is the 0-100 integer; serve_quality is the raw signed composite (~-0.3 to +0.3).
leaderboard <- serves %>%
  group_by(player, serve_team) %>%
  summarise(
    n_serves    = n(),
    avg_quality = round(mean(quality_index)),
    avg_p_ace   = round(mean(p_ace_oof), 3),
    avg_p_error = round(mean(p_error_oof), 3),
    avg_p_fbk   = round(mean(p_fbk_oof[in_play == 1L], na.rm = TRUE), 3),
    .groups = "drop"
  ) %>%
  filter(n_serves >= 10) %>%
  arrange(desc(avg_quality))

teams <- sort(unique(leaderboard$serve_team))

ui <- fluidPage(
  titlePanel("NCAA Volleyball Serve Quality Index — Cal Poly 2025"),
  
  sidebarLayout(
    sidebarPanel(
      selectInput("team", "Filter by Team:",
                  choices = c("All Teams", teams),
                  selected = "Cal Poly"),
      sliderInput("min_serves", "Minimum Serves:",
                  min = 10, max = 100, value = 10),
      hr(),
      p("Serve Quality = P(Ace) - P(Error) - P(In Play) \u00d7 P(FBK Against | In Play)"),
      p("Higher = better serving performance."),
      if (!is.null(val_metrics)) {
        tagList(
          hr(),
          strong("OOF Validation AUC"),
          tags$ul(
            tags$li(paste("M1 P(Ace):", val_metrics$auc_m1)),
            tags$li(paste("M2 P(Error):", val_metrics$auc_m2)),
            tags$li(paste("M3 P(FBK):", val_metrics$auc_m3))
          ),
          p(em(paste0("Holdout: last 20 matches (", val_metrics$n_test, " serves)")),
            style = "font-size:11px; color:#666;")
        )
      }
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel("Leaderboard",
                 br(),
                 tableOutput("leaderboard_table")
        ),
        tabPanel("Quality Chart",
                 br(),
                 plotOutput("quality_plot", height = "500px")
        ),
        tabPanel("FBK vs Ace",
                 br(),
                 plotOutput("scatter_plot", height = "500px")
        )
      )
    )
  )
)

server <- function(input, output) {
  
  filtered <- reactive({
    df <- leaderboard %>% filter(n_serves >= input$min_serves)
    if (input$team != "All Teams") {
      df <- df %>% filter(serve_team == input$team)
    }
    df
  })
  
  output$leaderboard_table <- renderTable({
    filtered() %>%
      arrange(desc(avg_quality)) %>%
      mutate(Rank = row_number()) %>%
      select(Rank, Player = player, Team = serve_team,
             Serves = n_serves, Quality = avg_quality,
             `P(Ace)` = avg_p_ace, `P(Error)` = avg_p_error,
             `P(FBK Against)` = avg_p_fbk)
  })
  
  output$quality_plot <- renderPlot({
    df <- filtered() %>% arrange(desc(avg_quality))
    if (input$team == "All Teams") df <- slice_head(df, n = 30)
    df$player <- factor(df$player, levels = df$player)
    cal_poly <- df$serve_team == "Cal Poly"
    
    ggplot(df, aes(x = player, y = avg_quality,
                   fill = ifelse(cal_poly, "Cal Poly", "Other"))) +
      geom_col() +
      scale_fill_manual(values = c("Cal Poly" = "#154734", "Other" = "#999999"),
                        name = "") +
      coord_flip() +
      labs(title = "Serve Quality by Player",
           x = NULL, y = "Average Serve Quality") +
      theme_minimal(base_size = 13)
  })
  
  output$scatter_plot <- renderPlot({
    df <- filtered()
    cal_poly <- df$serve_team == "Cal Poly"
    
    ggplot(df, aes(x = avg_p_fbk, y = avg_p_ace,
                   color = ifelse(cal_poly, "Cal Poly", "Other"),
                   size = n_serves)) +
      geom_point(alpha = 0.7) +
      ggrepel::geom_text_repel(
        data = df %>% filter(serve_team == "Cal Poly"),
        aes(label = player), size = 3, color = "#154734"
      ) +
      scale_color_manual(values = c("Cal Poly" = "#154734", "Other" = "#999999"),
                         name = "") +
      labs(title = "P(Ace) vs P(FBK Against)",
           x = "P(FBK Against) — lower is better",
           y = "P(Ace) — higher is better",
           size = "Serves") +
      theme_minimal(base_size = 13)
  })
}

shinyApp(ui = ui, server = server)
