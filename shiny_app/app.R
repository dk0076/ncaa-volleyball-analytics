library(shiny)
library(dplyr)
library(ggplot2)
library(ggrepel)

serves <- readRDS("../data/serve_quality.rds")

# Summarize for leaderboard — p_fbk averaged over in-play serves only (conditional rate)
leaderboard <- serves %>%
  group_by(player, serve_team) %>%
  summarise(
    n_serves    = n(),
    avg_quality = round(mean(serve_quality), 3),
    avg_p_ace   = round(mean(p_ace), 3),
    avg_p_error = round(mean(p_error), 3),
    avg_p_fbk   = round(mean(p_fbk[in_play == 1]), 3),
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
      p("Serve Quality = P(Ace) - P(Error) - P(FBK Against)"),
      p("Higher = better serving performance.")
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
