import FoundationModels
import Playgrounds

#Playground {
  let session = LanguageModelSession(instructions: """
      You are a world-class music journalist who writes short,
      descriptive song presentations.
      1. ONLY use information from the provided sections.
      2. DO NOT fabricate or alter names, titles, genres, dates, or claims.
      3. DO NOT add any information not present in the provided sections.
    """)

  print(try await session.respond(to: """
    [Song]\nAIZO\nKing Gnu\nAIZO - Single\nGenre: Alternative\nReleased: 2026-01-09\n[End Song]\n\n[TrackDescription]\n『呪術廻戦』第3期「死滅回游編」のオープニングテーマは、人気ロックバンド King Gnu による新曲「愛憎（AIZO）」です。ジャンプフェスタ'26での華々しい発表を経て、2026年1月9日に正式にリリースされました。「一途」や「SPECIALZ」に続き、King Gnuが本作のテーマ曲を手掛けるのはこれで3度目となります。楽曲面では、死滅回游の混沌とした緊張感と、生き残りをかけた凄惨な世界観を表現しています。King Gnu特有の重厚なロックサウンドと緻密なメロディが融合しており、歌詞ではタイトルの通り「愛」と「憎しみ」が表裏一体となった呪術師たちの葛藤や、残酷な運命が描かれています。MAPPAが制作した映像は、象徴的な演出と芸術的なオマージュが随所に散りばめられているのが特徴です。浮世絵師・歌川国芳の作品を彷彿とさせる和の伝統美を取り入れつつ、シリーズ特有の躍動感あふれるアクションシーンも健在です。物語がより複雑で悲劇的な展開へと突入する中、そのダークで成熟したトーンはファンから「シリーズ最高傑作の一つ」と高く評価されています。\n[End TrackDescription]\n\n[ArtistBio]\nKing Gnu (キングヌー) is a four member Japanese alternative rock band formed in Tokyo, 2013 formerly known as Mrs.Vinci (2013-2015) or Srv.Vinci (2015-2017).\n\nAfter switching up band members they changed their name to King Gnu on April 26, 2017 and began anew.\n[End ArtistBio]
    
        Task Overview: As a world-class music journalist, present this song to the user in 3 sentences in a descriptive writing tone.
        
    """
                                           , options: GenerationOptions(temperature: 0.5)
  ))
}


#Playground {
    let session = LanguageModelSession(instructions: """
    """)

    print(try await session.respond(to: """
    What is a world-class music journalist
    """))

}
