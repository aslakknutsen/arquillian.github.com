module Awestruct
  module Extensions
    module Keywords

      class Extractor
        def execute(site)

          @keyword_matchers = [TestMatcher.new, ModuleMatcher.new(site)]

          site.pages.each do |page|
            next unless page.guide

            page.keywords = locate_matches(page.content)
            puts page.keywords
          end

        end

        def locate_matches(content)
          matches = []
          @keyword_matchers.each do |matcher|
            matches = matches + matcher.find(content)
          end

          return matches
        end
      end

      class ModuleMatcher
        def initialize(site)
          @keywords = []

          site.pages.each do |page|
            next unless page.layout.eql? 'container-module'

            k = OpenStruct.new
            k.name = page.title
            k.link = "/#{page.output_path}"
            k.match = page.jira_version_prefix[0...-1]
            k.type = 'container'
            k.source = 'arquillian.org'

            @keywords << k
          end
        end

        def find(content)
          content.downcase!
          matches = []
          @keywords.each do |keyword|
            if content =~ /#{keyword.match}/
              matches << keyword
            end
          end
          return matches
        end

      end
      class TestMatcher

        def initialize()
          k1 = OpenStruct.new
          k1.name = 'Maven'
          k1.match = 'maven'
          k1.link = 'http://maven.apache.org'
          k1.source = 'test'
          k1.type = 'project'

          k2 = OpenStruct.new
          k2.name = 'JBoss Forge'
          k2.match = 'forge'
          k2.link = 'https://docs.jboss.org/author/display/FORGE/Home'
          k2.source = 'test'
          k2.type = 'project'

          k3 = OpenStruct.new
          k3.name = 'Weld'
          k3.match = 'weld'
          k3.link = 'http://seamframework.org/Weld'
          k3.source = 'test'
          k3.type = 'project'

          @keywords = [k1, k2, k3]
        end

        def find(content)
          content.downcase!
          matches = []
          @keywords.each do |keyword|
            if content =~ /#{keyword.match}/
              matches << keyword
            end
          end
          return matches
        end
      end
    end
  end
end
