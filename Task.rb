# Тут находится программа, выполняющая обработку данных из файла.
require 'minitest/autorun'
require 'date'
require 'json'

class User
  attr_reader :attributes, :sessions

  def initialize(attributes:, sessions:)
    @attributes = attributes
    @sessions = sessions
  end

  def full_name
    attributes[:first_name] + ' ' + attributes[:last_name]
  end
end

def parse_user(fields)
   {
      id: fields[1],
      first_name: fields[2],
      last_name: fields[3],
      age: fields[4],
  }
end

def parse_session(fields)
  parsed_result = {
      'user_id' => fields[1],
      'session_id' => fields[2],
      'browser' => fields[3],
      'time' => fields[4],
      'date' => fields[5],
  }
end

def collect_stats_from_users(report, users_objects, &block)
  users_objects.each do |user|
    user_key = "#{user.attributes['first_name']}" + ' ' + "#{user.attributes['last_name']}"
    report['usersStats'][user_key] ||= {}
    report['usersStats'][user_key] = report['usersStats'][user_key].merge(block.call(user))
  end
end

# как оно работает сейчас - с файла построчно (не закидая все водержимое в память) считываются данные юзера
# каждые save_every юзеров промежуточный репорт записывается в файл
# чтобы можно было продолжить считывание с места, если прервется выполнение (не имплементировано пока)
def lazy(path = 'data.txt', save_every = 100)
  line = 0
  user_stats = []
  user_count = 0

  file = File.open(path, "r")

  next_user = nil
  report = init_report

  # line - текущая линия файла. Если EOF, то метод считывания вернет -1
  while line != -1
    data = get_user_from_file(file, line, next_user)
    line = data[:ending_line]
    user = data[:user]
    user_count += 1
    next_user = data[:next_user]
    sessions = data[:sessions]
    user_object = User.new(attributes: user, sessions: sessions)
    user_stats = get_user_stats(user_object)
    p user_stats
    report = generate_report(user_stats, report)
    # сохранение промежуточных результатов
    save_report(report, line) if user_count % save_every
  end
  save_report(report, line)
end

# получаем данные о сессиях пользователя из файла
# считываем строки от user,... до user,...
# next user потому что мы указатель на строку файла не может быть возвращен назад,
# и окончание блока пользователя мы можем определить только началом следующего
def get_user_from_file(file, line, next_user)
  sessions = []
  user = []
  ending_line = line
  reached_other_user = false
  begin
    user = next_user || parse_user(file.readline.split(','))
    until reached_other_user
      current_line = file.readline
      ending_line += 1
      cols = current_line.split(',')
      sessions << parse_session(cols) if cols[0] == 'session'
      if cols[0] == 'user'
        reached_other_user = true
        new_user = parse_user(cols)
      end
    end
  rescue EOFError
    p 'end of the file reached'
    ending_line = -1
  # в случае ЕОФ мы возвращаем то, что успели вытянуть
  ensure
    data = {
        ending_line: ending_line,
        sessions: sessions,
        user: user,
        next_user: new_user,
    }
  end
  data
end

def get_user_stats(user)
  initial_stats = {
      user: user.full_name,
      sessionsCount: user.sessions.count,
      totalTime: user.sessions.map {|s| s['time']}.map {|t| t.to_i}.sum.to_s + ' min.',
      longestSession: user.sessions.map {|s| s['time']}.map {|t| t.to_i}.max.to_s + ' min.',
      browsers: user.sessions.map {|s| s['browser']}.map {|b| b.upcase}.sort,
      usedIE: user.sessions.map {|s| s['browser']}.any? {|b| b.upcase =~ /INTERNET EXPLORER/},
      alwaysUsedChrome: user.sessions.map {|s| s['browser']}.all? {|b| b.upcase =~ /CHROME/},
      dates: user.sessions.map {|s| s['date']}.map {|d| Date.parse(d)}.sort.reverse.map {|d| d.iso8601},
  }
  initial_stats
end

# этот метод сливает воедино данные пользователя и текущий репорт
def generate_report(user_stats, report)
  unique_browsers = (report[:allBrowsers].split(',') + user_stats[:browsers].flatten).uniq.sort
  report[:totalUsers] += 1
  report[:totalSessions] = user_stats[:sessionsCount] + report[:totalSessions]
  report[:allBrowsers] = unique_browsers.join(',')
  report[:uniqueBrowsersCount] = unique_browsers.count
  report[:usersStats] = report[:usersStats].merge(format_user_stats(user_stats))
  report
end

# обработка хэша данных пользователя для записи в джисон
def format_user_stats(user_stats)
  formatted_stats = {}
  name = user_stats.delete(:user)
  formatted_stats[name] = user_stats
  formatted_stats[name][:browsers] = user_stats[:browsers].join(', ')
  formatted_stats[name][:dates] = user_stats[:dates].map {|d| Date.parse(d)}.sort.reverse.map {|d| d.iso8601}
  formatted_stats
end

# создаем "пустой" репорт с дефолтными значениями в полях
def init_report
  {
      totalUsers: 0,
      uniqueBrowsersCount: 0,
      totalSessions: 0,
      allBrowsers: '',
      usersStats: {},
  }
end

# system создается для того, чтобы при обрыве парсинга можно было получить номер строки,
# на которой закончился последний успешный блок
def save_report(report, line)
  File.write('result.json', "#{report.to_json}\n")
  File.write('system', "#{line}\n")
end

class TestMe < Minitest::Test
  def setup
    File.write('result.json', '')
    File.write('data.txt',
               'user,0,Leida,Cira,0
session,0,0,Safari 29,87,2016-10-23
session,0,1,Firefox 12,118,2017-02-27
session,0,2,Internet Explorer 28,31,2017-03-28
session,0,3,Internet Explorer 28,109,2016-09-15
session,0,4,Safari 39,104,2017-09-27
session,0,5,Internet Explorer 35,6,2016-09-01
user,1,Palmer,Katrina,65
session,1,0,Safari 17,12,2016-10-21
session,1,1,Firefox 32,3,2016-12-20
session,1,2,Chrome 6,59,2016-11-11
session,1,3,Internet Explorer 10,28,2017-04-29
session,1,4,Chrome 13,116,2016-12-28
user,2,Gregory,Santos,86
session,2,0,Chrome 35,6,2018-09-21
session,2,1,Safari 49,85,2017-05-22
session,2,2,Firefox 47,17,2018-02-02
session,2,3,Chrome 20,84,2016-11-25
')
  end

  def test_result
    lazy
    expected_result_string = '{"totalUsers":3,"uniqueBrowsersCount":14,"totalSessions":15,"allBrowsers":"CHROME 13,CHROME 20,CHROME 35,CHROME 6,FIREFOX 12,FIREFOX 32,FIREFOX 47,INTERNET EXPLORER 10,INTERNET EXPLORER 28,INTERNET EXPLORER 35,SAFARI 17,SAFARI 29,SAFARI 39,SAFARI 49","usersStats":{"Leida Cira":{"sessionsCount":6,"totalTime":"455 min.","longestSession":"118 min.","browsers":"FIREFOX 12, INTERNET EXPLORER 28, INTERNET EXPLORER 28, INTERNET EXPLORER 35, SAFARI 29, SAFARI 39","usedIE":true,"alwaysUsedChrome":false,"dates":["2017-09-27","2017-03-28","2017-02-27","2016-10-23","2016-09-15","2016-09-01"]},"Palmer Katrina":{"sessionsCount":5,"totalTime":"218 min.","longestSession":"116 min.","browsers":"CHROME 13, CHROME 6, FIREFOX 32, INTERNET EXPLORER 10, SAFARI 17","usedIE":true,"alwaysUsedChrome":false,"dates":["2017-04-29","2016-12-28","2016-12-20","2016-11-11","2016-10-21"]},"Gregory Santos":{"sessionsCount":4,"totalTime":"192 min.","longestSession":"85 min.","browsers":"CHROME 20, CHROME 35, FIREFOX 47, SAFARI 49","usedIE":false,"alwaysUsedChrome":false,"dates":["2018-09-21","2018-02-02","2017-05-22","2016-11-25"]}}}' + "\n"
    expected_result = JSON.parse(expected_result_string)
    actual_result = JSON.parse(File.read('result.json'))

    assert_equal expected_result, actual_result
  end
end