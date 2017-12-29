defmodule Aida.Skill.ScheduledMessages do
  import Ecto.Query
  alias Aida.{Message, Repo, Channel, Session, Skill, BotManager, ChannelProvider}
  alias Aida.DB.SkillUsage
  alias __MODULE__

  @type t :: %__MODULE__{
    id: String.t(),
    bot_id: String.t(),
    name: String.t(),
    schedule_type: String.t(),
    messages: [Aida.DelayedMessage.t()]
  }

  defstruct id: "",
            bot_id: "",
            name: "",
            schedule_type: "",
            messages: []

  def delay(skill) do
    message = skill.messages
      |> Enum.min_by(fn(message) -> message.delay end)

    delay = (div(String.to_integer(message.delay), 2))
    delay = [delay, 24*60] |> Enum.min()
    delay = [delay, 20] |> Enum.max()

    :timer.minutes(delay)
  end

  def send_message(skill, session_id, last_usage) do
    {_, skill_message} = skill.messages
      |> Enum.map(fn(message) ->
        {Timex.shift(DateTime.utc_now(), minutes: String.to_integer("-#{message.delay}")), message.message}
      end)
      |> Enum.filter(fn({deadline, _message}) ->
        DateTime.compare(deadline, Timex.to_datetime(last_usage)) != :lt
      end)
      |> Enum.min_by(fn({deadline, _message}) ->
        DateTime.to_unix(deadline, :millisecond)
      end)

    channel = ChannelProvider.find_channel(session_id)

    SkillUsage.log_skill_usage(skill.bot_id, Skill.id(skill), session_id, false)

    session = Session.load(session_id)
    message = Message.new("", session)
    message = message |> Message.respond(skill_message)

    channel |> Channel.send_message(message.reply, session_id)
  end

  defimpl Aida.Skill, for: __MODULE__ do
    def init(skill, bot) do
      BotManager.schedule_wake_up(bot, skill, ScheduledMessages.delay(skill))
      skill
    end

    def wake_up(skill, bot) do
      skill_id = skill.id
      bot_id = bot.id
      reminder_deadlines = skill.messages
        |> Enum.map(fn(message) ->
          Timex.shift(DateTime.utc_now(), minutes: String.to_integer("-#{message.delay}"))
        end)

      reminded_users = SkillUsage
        |> where([s], s.skill_id == ^skill_id and s.bot_id == ^bot_id)
        |> select([s], s.user_id)
        |> Repo.all()

      never_reminded = reminder_deadlines
        |> Enum.reduce((SkillUsage
          |> group_by([s], s.user_id)
          |> select([s], {s.user_id, max(s.last_usage)})
          |> where([s], not(s.user_id in ^reminded_users))
          |> where([s], s.bot_id == ^bot_id)), fn(deadline, query) ->
          query
          |> or_having([s], max(s.last_usage) < ^deadline)
        end)
        |> Repo.all()

      due_reminder = reminder_deadlines
        |> Enum.reduce((SkillUsage
          |> join(:inner, [s], t in SkillUsage, s.user_id == t.user_id and s.bot_id == t.bot_id)
          |> group_by([s, t], s.user_id)
          |> select([s, t], {s.user_id, max(s.last_usage), max(t.last_usage)})
          |> where([s, t], t.bot_id == ^bot_id)
          |> where([s, t], t.skill_id == ^skill_id)
          |> where([s, t], t.user_id in ^reminded_users)), fn(deadline, query) ->
          query
          |> or_having([s], max(s.last_usage) < ^deadline)
        end)
        |> Repo.all()

      never_reminded
        |> Enum.each(fn({user, last_usage}) ->
          ScheduledMessages.send_message(skill, user, last_usage)
        end)

      due_reminder
        |> Enum.each(fn({user, last_usage, _last_reminder}) ->
          ScheduledMessages.send_message(skill, user, last_usage)
        end)

      BotManager.schedule_wake_up(bot, skill, ScheduledMessages.delay(skill))
      :ok
    end

    def explain(%{}, message) do
      message
    end

    def clarify(%{}, message) do
      message
    end

    def put_response(%{}, message) do
      message
    end

    def confidence(%{}, _message) do
      0
    end

    def id(%{id: id}) do
      id
    end
  end
end
