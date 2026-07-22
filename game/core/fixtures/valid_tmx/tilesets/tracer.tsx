<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.11" tiledversion="1.11.2" name="tracer" tilewidth="16" tileheight="16" tilecount="24" columns="8">
 <properties>
  <property name="pokeredpc:block_size" type="int" value="2"/>
  <property name="third-party:palette" value="fixture"/>
 </properties>
 <image source="../assets/tracer.png" width="128" height="48"/>
 <tile id="0">
  <properties>
   <property name="pokeredpc:walkable" type="bool" value="true"/>
   <property name="pokeredpc:feet_tile" type="int" value="16"/>
   <property name="pokeredpc:block" value="path:0,0"/>
  </properties>
 </tile>
 <tile id="1">
  <properties>
   <property name="pokeredpc:walkable" type="bool" value="false"/>
   <property name="pokeredpc:feet_tile" type="int" value="1"/>
   <property name="pokeredpc:block" value="wall:0,0"/>
  </properties>
 </tile>
</tileset>
