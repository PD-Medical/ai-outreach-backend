/**
 * Weather Tool
 * Gets current weather information for a given city
 */

import { tool } from "langchain"
import { z } from "zod"

export const weatherTool = tool(
  (input: { city: string }) => {
    // TODO: Replace with actual weather API call
    // Example: OpenWeatherMap, WeatherAPI, etc.
    return `The weather in ${input.city} is sunny with a temperature of 72°F (22°C).`
  },
  {
    name: "get_weather",
    description: "Get the current weather for a given city. Use this when the user asks about weather conditions.",
    schema: z.object({
      city: z.string().describe("The city to get the weather for"),
    }),
  }
)

