defmodule Aida.Bot do
  alias Aida.{FrontDesk, Variable, Message, Skill, Logger, DB.SkillUsage}
  alias __MODULE__

  @type message :: map

  @type t :: %__MODULE__{
    id: String.t,
    languages: [String.t],
    front_desk: FrontDesk.t,
    skills: [map],
    variables: [Variable.t],
    channels: []
  }

  defstruct id: nil,
            languages: [],
            front_desk: %FrontDesk{},
            skills: [],
            variables: [],
            channels: []

  @spec init(bot :: t) :: {:ok, t}
  def init(bot) do
    skills = bot.skills
      |> Enum.map(fn(skill) ->
        Skill.init(skill, bot)
      end)

    {:ok, %{bot | skills: skills}}
  end

  @spec wake_up(bot :: t, skill_id :: String.t) :: :ok
  def wake_up(%Bot{} = bot, skill_id) do
    find_skill(bot, skill_id)
      |> Skill.wake_up(bot)
  end

  @spec chat(bot :: t, message :: Message.t) :: Message.t
  def chat(%Bot{} = bot, %Message{} = message) do
    message = if !(Message.language(message) in bot.languages) do
                Message.put_session(message, "language", nil)
              else
                message
              end

    cond do
      !Message.language(message) && Enum.count(bot.languages) == 1 ->
        message
          |> Message.put_session("language", bot.languages |> List.first)
          |> FrontDesk.greet(bot)
      Message.language(message) ->
        handle(bot, message)
      true -> language_detector(bot, message)
    end
  end

  defp handle(bot, message) do
    skills_sorted = bot
      |> relevant_skills(message.session)
      |> Enum.map(&(evaluate_confidence(&1, bot, message)))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn (skill) -> skill.confidence end, &>=/2)

    case skills_sorted do
      [] -> message |> FrontDesk.not_understood(bot)
      skills ->
        higher_confidence_skill = Enum.at(skills, 0)

        difference = case Enum.count(skills) do
          1 -> higher_confidence_skill.confidence
          _ -> higher_confidence_skill.confidence - Enum.at(skills, 1).confidence
        end

        if threshold(bot) <= difference do
          Skill.respond(higher_confidence_skill.skill, message)
        else
          message |> FrontDesk.clarification(bot, Enum.map(skills, fn(skill) -> skill.skill end))
        end
    end
  end

  defp evaluate_confidence(skill, bot, message) do
    confidence = Skill.confidence(skill, message)
    case confidence do
      :threshold ->
        %{confidence: threshold(bot), skill: skill}
      confidence when confidence > 0 ->
        %{confidence: confidence, skill: skill}
      _ -> nil
    end
  end

  def relevant_skills(bot, session) do
    bot.skills
      |> Enum.filter(&(Skill.is_relevant?(&1, session)))
  end

  defp language_detector(bot, message) do
    skills = bot.skills |> Enum.filter(&is_language_detector?/1)

    case skills do
      [skill] ->
        if Skill.confidence(skill, message) > 0 do
          Skill.respond(skill, message)
            |> FrontDesk.greet(bot)
        else
          SkillUsage.log_skill_usage(bot.id, Aida.Skill.id(skill), message.session.id)
          Skill.explain(skill, message)
        end
      _ -> Logger.info "Error: None or more than one language_detector skills were found"
    end
  end

  def is_language_detector?(%Skill.LanguageDetector{})do
    true
  end

  def is_language_detector?(_)do
    false
  end

  defp find_skill(bot, skill_id) do
    skills = bot.skills
      |> Enum.filter(fn(skill) ->
        Skill.id(skill) == skill_id
      end)

    case skills do
      [skill] -> skill
      [] -> Logger.info "Skill not found #{skill_id}"
      _ -> Logger.info "Duplicated skill id #{skill_id}"
    end
  end

  def threshold(%Bot{front_desk: front_desk}) do
    front_desk |> FrontDesk.threshold
  end

  def lookup_var(%Bot{variables: variables}, session, key) do
    variable =
      variables
      |> Enum.find(fn var -> var.name == key end)

    if variable do
      variable |> Variable.resolve_value(session)
    end
  end
end
