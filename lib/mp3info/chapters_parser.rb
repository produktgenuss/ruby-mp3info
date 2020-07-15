require 'date'
require 'mp3info/frame'
require 'httparty'

class Mp3Info
  # accepts list of
  # [['00:00:00.000', 'title', 'url', 'image_path'], ..]
  self.send(:remove_const, :ChaptersParser) rescue nil
  class ChaptersParser

    self.send(:remove_const, :Chapter) rescue nil
    class Chapter
      attr_reader :start, :finish, :title, :url, :image_path

      def initialize(id, start, finish, title, url, image_path)
        @id, @start, @finish, @title, @url, @image_path = id, start, finish, title, url, image_path
      end

      def chap
        Mp3Info::Frame::Chapter.new(
          :id => id,
          :start => start,
          :finish => finish,
          :sub_frames => sub_frames
        )
      end

      private

      def id
        Mp3Info::Frame::StringzToSym.new(@id)
      end

      def sub_frames
        [tit2, wxxx, image].compact
      end

      def tit2
        Mp3Info::Frame::SubFrame.new(
          :name => "TIT2".encode("ASCII-8BIT"),
          :body => Mp3Info::Frame::Tit2.new(
            :encoding_index => 1,
            :title => Mp3Info::Frame::StringUtf16.new(title))
        )
      end

      def wxxx
        return if url.blank?

        Mp3Info::Frame::SubFrame.new(
          :name => "WXXX".encode("ASCII-8BIT"),
          :body => Mp3Info::Frame::Link.new(
            :encoding_index => 0,
            :href => {
              :text => Mp3Info::Frame::StringUtf16.new("chapter url"),
              :url => Mp3Info::Frame::StringUtf16.new(url)
            })
        )
      end

      def image
        return if image_path.blank?

        if image_path.starts_with?('http')
          file = Tempfile.new
          File.open(file, 'wb') do |f|
            f.write HTTParty.get(image_path).body
          end
          file_path = file.path
        else
          file_path = image_path
        end

        Mp3Info::Frame::SubFrame.new(
          :name => "APIC".encode("ASCII-8BIT"),
          :body => Mp3Info::Frame::Apic.new(
            :encoding_index => 0,
            :mime => "image/jpeg",
            :image_type => 0,
            :description => "Chapter Image",
            :data => File.read(file_path)
          )
        )
      end


    end

    attr_reader :tlen, :chapters, :ctocs, :chaps
    TOC = :toc

    def initialize(tlen, chapters)
      @tlen, @chapters = tlen.to_i, chapters
      @chaps = {}
      @ctocs = { TOC => top_ctoc }
      parse!
    end

    private

    def parse!
      return unless @chaps.empty?
      (chapters + [nil]).each_cons(2).each_with_index do |((start, title, url, image_path), (finish, _)), i|
        id = "chp#{i}".to_sym
        finish_ms = finish ? to_ms(finish) : tlen
        chapter = Chapter.new(id, to_ms(start), finish_ms, title, url, image_path)
        @chaps[id] = chapter.chap
        add_to_top_ctoc!(id)
      end
    end

    def add_to_top_ctoc!(sym_id)
      @ctocs[TOC][:children_ids] << Mp3Info::Frame::StringzToSym.new(sym_id)
    end

    def top_ctoc
      Mp3Info::Frame::Toc.new(
        :id => Mp3Info::Frame::StringzToSym.new(TOC),
        :flags => Mp3Info::Frame::TocFlags.new(:top => true, :ordered => true),
        :children_ids => []
      )
    end

    def to_ms(hh_mm_ss_ms)
      DateTime.strptime("1970-01-01 #{hh_mm_ss_ms}", "%Y-%m-%d %H:%M:%S.%L").strftime("%Q").to_i
    rescue => e
      # require 'pry'; binding.pry if $DEBUG
    end
  end
end
