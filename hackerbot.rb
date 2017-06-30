require 'cinch'
require 'nokogiri'
require 'nori'
require './print.rb'
require 'open3'

def read_bots
  bots = {}
  Dir.glob("config/*.xml").each do |file|
    print "#{file}"

    begin
      doc = Nokogiri::XML(File.read(file))
    rescue
      Print.err "Failed to read hackerbot file (#{file})"
      print "Failed to read hackerbot file (#{file})"

      exit
    end
    #
    # # TODO validate scenario XML against schema
    # begin
    #   xsd = Nokogiri::XML::Schema(File.read(schema_file))
    #   xsd.validate(doc).each do |error|
    #     Print.err "Error in #{module_type} metadata file (#{file}):"
    #     Print.err '    ' + error.message
    #     exit
    #   end
    # rescue Exception => e
    #   Print.err "Failed to validate #{module_type} metadata file (#{file}): against schema (#{schema_file})"
    #   Print.err e.message
    #   exit
    # end

    # remove xml namespaces for ease of processing
    doc.remove_namespaces!

    doc.xpath('/hackerbot').each_with_index do |hackerbot|

      bot_name = hackerbot.at_xpath('name').text
      Print.debug bot_name
      bots[bot_name] = {}
      bots[bot_name]['greeting'] = hackerbot.at_xpath('greeting').text
      bots[bot_name]['hacks'] = []
      hackerbot.xpath('//hack').each do |hack|
        bots[bot_name]['hacks'].push Nori.new.parse(hack.to_s)['hack']

      end
      bots[bot_name]['current_hack'] = 0

      Print.debug bots[bot_name]['hacks'].to_s

      bots[bot_name]['bot'] = Cinch::Bot.new do
        configure do |c|
          c.nick = bot_name
          c.server = 'localhost' # "irc.freenode.org" TODO
          c.channels = ['#hackerbottesting']
        end

        on :message, 'hello' do |m|
          m.reply "Hello, #{m.user.nick}."
          m.reply bots[bot_name]['greeting']
          current = bots[bot_name]['current_hack']

          # prompt for the first attack
          m.reply bots[bot_name]['hacks'][current]['prompt']
          m.reply "When you are ready, simply say 'ready'."
        end

        on :message, 'help' do |m|
          m.reply "Hello, #{m.user.nick}."
          m.reply "I am waiting for you to say 'ready', 'next', or 'previous'"
        end

        on :message, 'next' do |m|
          m.reply "Ok, I'll do what I can to move things along..."

          # TODO: remove this repetition (move to function?)
          # is this the last one?
          if bots[bot_name]['current_hack'] < bots[bot_name]['hacks'].length - 1
            bots[bot_name]['current_hack'] += 1
            current = bots[bot_name]['current_hack']

            # prompt for current hack
            m.reply bots[bot_name]['hacks'][current]['prompt']
            m.reply "When you are ready, simply say 'ready'."

          else
            m.reply "That's the last attack for now. You can rest easy, until next time..."
          end

        end

        on :message, 'previous' do |m|
          m.reply "Ok, I'll do what I can to move things along..."

          # is this the last one?
          if bots[bot_name]['current_hack'] > 0
            bots[bot_name]['current_hack'] -= 1
            current = bots[bot_name]['current_hack']

            # prompt for current hack
            m.reply bots[bot_name]['hacks'][current]['prompt']
            m.reply "When you are ready, simply say 'ready'."

          else
            m.reply 'You are back to the beginning...'
          end

        end

        on :message, 'list' do |m|


        end

        on :message, 'ready' do |m|
          m.reply 'Ok. Gaining shell access, and running post command...'
          current = bots[bot_name]['current_hack']
          # cmd_output = `#{bots[bot_name]['hacks'][current]['get_shell']} << `

          shell_cmd = bots[bot_name]['hacks'][current]['get_shell']
          Print.debug shell_cmd

          Open3.popen2e(shell_cmd) do |stdin, stdout_err|
            # check whether we have shell by echoing "test"
            sleep(1)
            stdin.puts "echo shelltest\n"
            sleep(1)
            line = stdout_err.gets.chomp()
            if line == "shelltest"
              m.reply 'We are in to your system...'

              post_cmd = bots[bot_name]['hacks'][current]['post_command']
              if post_cmd
                stdin.puts "#{post_cmd}\n"
              end

              # sleep(1)
              line = stdout_err.gets.chomp()
              m.reply line
              condition_met = false
              bots[bot_name]['hacks'][current]['condition'].each do |condition|
                if !condition_met && condition.key?('output_contains') && line.include?(condition['output_contains'])
                  condition_met = true
                  # m.reply "(#{line}) contains (#{condition['output_contains']})"
                  # if line =~ /condition['output_contains']/
                  m.reply "#{condition['message']}"
                  if condition.key?('trigger_next')
                    # is this the last one?
                    if bots[bot_name]['current_hack'] < bots[bot_name]['hacks'].length - 1
                      bots[bot_name]['current_hack'] += 1
                      current = bots[bot_name]['current_hack']

                      sleep(1)
                      # prompt for current hack
                      m.reply bots[bot_name]['hacks'][current]['prompt']

                    else
                      m.reply "That's the last attack for now. You can rest easy, until next time..."
                    end
                  end
                end
                if !condition_met && condition.key?('output_equals') && line == condition['output_equals']
                  condition_met = true
                  # m.reply "(#{line}) equals (#{condition['output_contains']})"
                  # if line =~ /condition['output_contains']/
                  m.reply "#{condition['message']}"

                  # TODO: remove this repetition (move to function?)
                  if condition.key?('trigger_next')
                    # is this the last one?
                    if bots[bot_name]['current_hack'] < bots[bot_name]['hacks'].length - 1
                      bots[bot_name]['current_hack'] += 1
                      current = bots[bot_name]['current_hack']

                      sleep(1)
                      # prompt for current hack
                      m.reply bots[bot_name]['hacks'][current]['prompt']

                    else
                      m.reply "That's the last attack for now. You can rest easy, until next time..."
                    end
                  end

                end
              end
              unless condition_met
                if bots[bot_name]['hacks'][current]['else_condition']
                  m.reply bots[bot_name]['hacks'][current]['else_condition']['message']
                end
              end


            else
              m.reply bots[bot_name]['hacks'][current]['shell_fail_message']
            end

          end
          m.reply "Let me know when you are 'ready', if you are ready to move on to another attack, say 'next', or 'previous' and I'll move things along"
        end
      end
    end
  end

  bots
end

def start_bots(bots)
  bots.each do |bot_name, bot|
    Print.std "Starting bot: #{bot_name}\n"
    bot['bot'].start
  end
end

bots = read_bots
start_bots(bots)
